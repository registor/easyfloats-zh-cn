#!/usr/bin/env python3

# Copyright © 2020 E. Zöllner
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See ./license.txt for more details.

"""
This program compiles TeX files and
checks the output for errors, warnings
and overfull/underfull boxes.
preamble/testmarkup.tex defines macros
to declare expected errors and warnings.
The environment variable TEXINPUTS is
set so that TeX will preferably load a
development version of a package located
in the parent directory instead of a
system wide installed package.

Before running the tests this program
looks for a batch file which (if found)
is executed with tex in order to extract
the sty file from a dtx file.
This batch file should either have the
extension ins or be included in the dtx file.
For more information about dtx, sty and ins
files and docstrip see
https://www.texdev.net/2009/10/05/the-dtx-format/
https://www.texdev.net/2009/10/06/a-model-dtx-file/
texdoc docstrip

Magic comments at the top of a TeX file
can be used to specify the TeX engine
and command line arguments to be used.
(Inspired by http://texstudio.sourceforge.net/manual/current/usermanual_en.html#SECTION_TEXCOM)
`% !TeX program = pdflatex` defines the executable to be used.
`% !TeX option = --shell-escape` sets a command line argument.
For security reasons only the values defined
in MagicCommentExtractor.allowed_programs
and MagicCommentExtractor.allowed_options
are allowed.
If `TeX program` is unspecified
MagicCommentExtractor.program is used.

If a warning is recognized that a rerun is necessary
that rerun is performed automatically.

This program shows a progress bar in square brackets.
A dot stands for a successful test,
an `F' for a failed test
and an `E' for an error in this program.
"""

import re
import os
import subprocess
import traceback
import datetime

# The first existing directory in this list is used as test directory.
# All tex files in that directory will be treated as system under test.
dirs_test = ['test', '.']
# The directories to be searched for the ins file (before the tests)
dirs_ins  = ['.', '..']
# The directories to be searched preferably for the sty file (during the tests)
dirs_sty = dirs_ins
# A list of functions which decide whether a given file name belongs to a docstrip batch file
# (Later functions are tried only if earlier functions do not return any results)
list_is_ins_filename = [lambda fn: fn.lower().endswith('.ins'), lambda fn: fn.lower().endswith('.dtx')]


os.environ['TEXINPUTS'] = os.pathsep.join(dirs_sty) + os.pathsep

file_encoding = "utf8"
shell_encoding = "utf8"
tex_encoding = {
	#https://stackoverflow.com/questions/56734934/unicodedecodeerror-with-0xc3-in-python-subprocess-stdout-in-macos/56735278#comment100033782_56735278
	"pdflatex" : "ISO-8859-2",
	None       : shell_encoding,
}


class Issue:

	ELLIPSIS = " ..."
	LEN_ELLIPSIS = len(ELLIPSIS)

	__slots__ = ('level', 'expected', 'msg')

	def __str__(self):
		return "%s%s" % ("expecting " if self.expected else "", self.level)

	def __eq__(self, other):
		# independent of self.expected
		# (I am assuming other is the expected and there msg may be abbreviated)
		if self.ELLIPSIS in other.msg:
			return self.level == other.level and re.match("^%s$" % re.escape(other.msg).replace(re.escape(self.ELLIPSIS), ".*"), self.msg)
		else:
			return self.level == other.level and self.msg == other.msg

	def is_rerun_request(self):
		if self.level == TexLogReader.LEVEL_WARNING:
			if "Label(s) may have changed" in self.msg:
				return True
			if "run LaTeX again" in self.msg:
				return True
			if "Rerun LaTeX" in self.msg:
				return True

		return False


def iter_lines(stream, encoding):
	#https://stackoverflow.com/a/2813530
	while True:
		ln = stream.readline()
		if not ln:
			break

		ln = ln.decode(encoding)
		yield ln


class MagicCommentExtractor:

	program = "pdflatex"

	number_lines_to_search_for_magic_comment = 5

	reo_magic_comment_program = re.compile(r"program\s*=\s*(?P<program>\S+)")
	reo_magic_comment_option = re.compile(r"option\s*=\s*(?P<option>\S+)")

	allowed_programs = ("pdflatex", "xelatex", "lualatex", "latex", "tex")
	allowed_options = ("--shell-escape", "--8bit")

	def __init__(self, fn):
		self.fn = fn

	def get_cmd(self):
		program = self.program
		options = ['--interaction=nonstopmode']

		for ln in self.iter_lines():
			m = self.reo_magic_comment_program.search(ln)
			if m:
				tmp = m.group("program")
				if not self.is_allowed_program(tmp):
					raise ValueError("Unknown latex compiler program %s. I will not try running it for security reasons." % tmp)

				program = tmp
				continue

			m = self.reo_magic_comment_option.search(ln)
			if m:
				tmp = m.group("option")
				if not self.is_allowed_option(tmp):
					raise ValueError("Unknown latex compiler option %s. I am ignoring it." % tmp)
					continue

				options.append(tmp)
				continue

		cmd = options
		cmd.insert(0, program)
		cmd.append(self.fn)
		return cmd

	def iter_lines(self):
		with open(self.fn, "rt", encoding=file_encoding) as f:
			for i, ln in enumerate(f):
				yield ln

				if i >= self.number_lines_to_search_for_magic_comment:
					break

	def is_allowed_program(self, name):
		return name in self.allowed_programs

	def is_allowed_option(self, name):
		if not name.startswith("--"):
			name = "-" + name
		return name in self.allowed_options


class TexLogReader:

	reo_error = re.compile('^(! )(?P<prefix>.* Error:)?')
	reo_error_line_number = re.compile(r'^l.\d+')
	reo_warning = re.compile('.*Warning:')
	reo_invalid_box = re.compile('(under|over)full [hv]box')
	reo_expecting = re.compile('(?P<prefix># Expecting )(Package (?P<packagename>.*) |LaTeX )?(?P<type>Warning|Error)')

	EXPECTING = True
	OCCURED   = False
	LEVEL_ERROR = 'error'
	LEVEL_WARNING = 'warning'
	LEVEL_SPACING = 'spacing'

	STATE_NORMAL = 0
	STATE_APPEND = 1
	STATE_APPEND_ERROR = 2
	STATE_SEARCH_ERROR_LINE_NUMBER = 3
	STATE_OUT = -1


	# --------- constructor ---------

	def __init__(self, fn):
		self.fn = fn


	# --------- parse file ---------

	def compile(self):
		self.reset_msg()
		state = self.STATE_NORMAL
		for ln in self.iter_lines():
			ln = ln.rstrip('\n')
			ln = ln.rstrip('\r')
			if state == self.STATE_NORMAL:
				state = self.parse_line_normal(ln)
			elif state == self.STATE_APPEND:
				state = self.parse_line_append(ln)
			elif state == self.STATE_APPEND_ERROR:
				state = self.parse_line_append_error(ln)
			elif state == self.STATE_SEARCH_ERROR_LINE_NUMBER:
				state = self.parse_line_search_error_line_number(ln)
			else:
				assert False

			if state == self.STATE_OUT:
				yield self.get_issue()
				self.reset_msg()
				state = self.STATE_NORMAL

		if state != self.STATE_NORMAL:
			yield self.get_issue()

	def iter_lines(self):
		cmd = MagicCommentExtractor(self.fn).get_cmd()
		p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
		encoding = tex_encoding.get(cmd[0], None)
		for ln in iter_lines(p.stdout, encoding):
			yield ln


	def parse_line_normal(self, ln):
		m = self.reo_expecting.match(ln)
		if m:
			expected_type = m.group('type')
			if expected_type == 'Error':
				self.set_type(self.EXPECTING, self.LEVEL_ERROR)
			elif expected_type == 'Warning':
				self.set_type(self.EXPECTING, self.LEVEL_WARNING)
			else:
				assert False

			self.append(ln[m.end('prefix'):])
			return self.STATE_APPEND

		m = self.reo_error.match(ln)
		if m:
			self.set_type(self.OCCURED, self.LEVEL_ERROR)
			if not m.group("prefix"):
				prefix = "Error: "
			else:
				prefix = ""
			self.append(prefix + ln[m.end(1):])
			return self.STATE_APPEND_ERROR

		m = self.reo_warning.match(ln)
		if m:
			self.set_type(self.OCCURED, self.LEVEL_WARNING)
			self.append(ln)
			return self.STATE_APPEND

		m = self.reo_invalid_box.match(ln)
		if m:
			self.set_type(self.OCCURED, self.LEVEL_SPACING)
			self.append(ln)
			return self.STATE_OUT

		return self.STATE_NORMAL

	def parse_line_append(self, ln):
		if not ln:
			return self.STATE_OUT
		if ln[:2].isspace():
			return self.STATE_OUT

		self.append(ln)
		return self.STATE_APPEND


	def parse_line_append_error(self, ln):
		state = self.parse_line_search_error_line_number(ln)
		if state == self.STATE_OUT:
			return state

		state = self.parse_line_append(ln)
		if state == self.STATE_OUT:
			return self.STATE_SEARCH_ERROR_LINE_NUMBER
		elif state == self.STATE_APPEND:
			return self.STATE_APPEND_ERROR
		else:
			assert False

	def parse_line_search_error_line_number(self, ln):
		m = self.reo_error_line_number.match(ln)
		if m:
			line_number = m.group()
			line_number = "# %s" % line_number
			self.append(line_number)
			return self.STATE_OUT

		return self.STATE_SEARCH_ERROR_LINE_NUMBER


	# --------- cache ---------

	def set_type(self, expected, level):
		self._issue.level = level
		self._issue.expected = expected
	
	def get_issue(self):
		self._issue.msg = self.get_msg()
		return self._issue


	def reset_msg(self):
		self._issue = Issue()
		self.msg = list()

	def append(self, text):
		self.msg.append(text)
		#self.msg.append(" ")

	def get_msg(self):
		return "".join(self.msg)


class CommandLineUI:

	TEST_OPEN    = ' '
	TEST_SUCCESS = '.'
	TEST_FAILURE = 'F'
	TEST_ERROR   = 'E'

	INDENTATION  = '\t'


	def __init__(self, number_tests):
		self.tests = [self.TEST_OPEN for i in range(number_tests)]
		self.update_test_progress()
		self.test_index = 0
		test_progresss_len = number_tests + 2
		self.test_progress_eraser = " " * test_progresss_len

	def update_test_progress(self):
		self.test_progress = "[%s]" % "".join(self.tests)

	def print_progress(self):
		print(self.test_progress, end='\r', flush=True)

	def overwrite_progress(self):
		print(self.test_progress_eraser, end='\r')

	def indent(self, msg):
		return "\n".join(self.INDENTATION + ln for ln in msg.splitlines())


	# --------- interface ---------

	def test_start(self, tex_filename, retry=0):
		if retry:
			retry = " (retry %s)" % retry
		else:
			retry = ""

		self.tex_filename = tex_filename
		self.failed = False

		self.overwrite_progress()
		print(tex_filename + retry)
		self.print_progress()

	def unexpected(self, issue):
		assert not issue.expected
		self.failed = True
		msg = "Unexpected       " + issue.msg
		msg = self.indent(msg)
		self.overwrite_progress()
		print(msg)
		self.print_progress()

	def missing(self, issue):
		assert issue.expected
		self.failed = True
		msg = "Missing expected " + issue.msg
		msg = self.indent(msg)
		self.overwrite_progress()
		print(msg)
		self.print_progress()

	def test_end(self, error=None):
		self.overwrite_progress()
		if isinstance(error, BaseException):
			result = self.TEST_ERROR

			msg = traceback.format_exception(type(error), error, error.__traceback__)
			msg = "\n".join(msg)
			msg = self.indent(msg)
			print(msg)

		elif error:
			result = self.TEST_ERROR
			msg = "ERROR: %s" % error
			msg = self.indent(msg)
			print(msg)

		elif self.failed:
			result = self.TEST_FAILURE

		else:
			result = self.TEST_SUCCESS

		print()

		self.tests[self.test_index] = result
		self.update_test_progress()
		self.test_index += 1
		self.print_progress()


class Controller:

	EXT = ".tex"
	MAX_RETRIES = 3

	def __init__(self, paths, *, max_retries=None, ui=None):
		if max_retries is not None:
			self.MAX_RETRIES = max_retries

		self.root_directory = os.getcwd()
		self.filenames = list()
		for p in paths:
			if os.path.isdir(p):
				fns = list(self.iter_filenames(p))
				fns.sort()
				self.filenames.extend(fns)
			elif os.path.isfile(p):
				self.filenames.append(p)
			elif os.path.isfile(p + self.EXT):
				self.filenames.append(p + self.EXT)
			elif p[-1:] == '.' and os.path.isfile(p[:-1] + self.EXT):
				self.filenames.append(p[:-1] + self.EXT)
			else:
				# is handled in test_one_file
				self.filenames.append(p)

		if ui:
			self.ui = ui
		else:
			self.ui = CommandLineUI(len(self.filenames))

	def test_one_file(self, path, fn, retries=0):
		self.ui.test_start(os.path.join(path, fn), retries)
		if not os.path.isfile(fn):
			self.ui.test_end(error="no such file")
			return

		expected = []
		retry = False
		for issue in TexLogReader(fn).compile():
			if retry:
				# wait until this run has finished
				continue

			if issue.expected:
				expected.append(issue)
				continue

			while len(expected) > 0:
				expected_issue = expected[0]
				if issue == expected_issue:
					del expected[0]
					break
				else:
					self.ui.missing(expected_issue)
					del expected[0]
			else:
				if retries < self.MAX_RETRIES and issue.is_rerun_request():
					retry = True
				else:
					self.ui.unexpected(issue)

		if retry:
			self.test_one_file(path, fn, retries+1)
			return

		for expected_issue in expected:
			self.ui.missing(expected_issue)

		self.ui.test_end()

	def iter_filenames(self, path):
		for fn in os.listdir(path):
			if not os.path.splitext(fn)[1] == self.EXT:
				continue

			ffn = os.path.join(path, fn)
			if not os.path.isfile(ffn):
				continue

			yield ffn

	def test_all(self):
		for ffn in self.filenames:
			path, fn = os.path.split(ffn)
			if path:
				os.chdir(path)

			try:
				self.test_one_file(path, fn)
			except Exception as e:
				self.ui.test_end(e)

			os.chdir(self.root_directory)

		# do not overwrite progress with next prompt
		print()


def find_ins_file():
	'''
	A LaTeX package is usually written in a dtx file.
	This function is searching for a batch file which
	if executed with tex extracts the sty file from
	the dtx file using docstrip.
	'''
	for d in dirs_ins:
		fns_unfiltered = os.listdir(d)
		for is_ins_filename in list_is_ins_filename:
			fns = [fn for fn in fns_unfiltered if is_ins_filename(fn)]
			n = len(fns)
			if n > 1:
				print("too many batch files found in directory %s: %s" % (d, ", ".join(fns)))
				return None
			elif n == 1:
				fn = fns[0]
				fn = os.path.join(d, fn)
				return fn

	print("Warning: no batch file found")
	return None

def extract_sty(fn_ins):
	path, fn = os.path.split(fn_ins)

	cmd = ('tex', fn)
	print("trying to (re)generate sty file with `%s` in %s" % (" ".join(cmd), path))
	subprocess.run(cmd, check=True, cwd=path)
	print("")


class CtanExport:

	ext = ".zip"
	re_ctan_name = r'^[a-z][a-z0-9-]+$'

	def __init__(self, ctan_name):
		assert ctan_name, "ctan_name is %r" % ctan_name

		if os.path.isdir(ctan_name):
			ctan_name = os.path.abspath(ctan_name)
			path = ctan_name
			ctan_name = os.path.split(ctan_name)[1]
		elif os.path.isfile(ctan_name):
			path, ctan_name = os.path.split(ctan_name)
			ctan_name = os.path.splitext(ctan_name)[0]
			if not path:
				path = os.path.curdir
		else:
			path = os.path.curdir
			ctan_name = ctan_name

		self.ctan_name = ctan_name
		self.path_to_be_exported = path

	def create_archive(self):
		changes, untracked = self.git_status()
		assert not changes, "There are uncommitted changes which would not be exported"
		if untracked:
			print("WARNING: There are untracked files which are not exported")

		styfn = self.ctan_name + '.sty'
		path = self.path_to_be_exported
		assert re.match(self.re_ctan_name, self.ctan_name), "Invalid CTAN name: %s" % self.ctan_name
		assert os.path.isfile(os.path.join(path, styfn)), "%s does not contain a file called %s" % (path, styfn)

		archive_name = self.ctan_name + self.ext
		archive_name = os.path.abspath(archive_name)
		prefix = self.ctan_name + '/'
		cmd = ('git', 'archive', '-o', archive_name, '--prefix', prefix, 'HEAD')
		print("generate CTAN archive %s" % archive_name)
		subprocess.run(cmd, check=True, cwd=path)
		print("")

		self.archive = os.path.join(path, archive_name)

	def test_archive(self):
		import tempfile
		with tempfile.TemporaryDirectory() as path:
			cmd = ('aunpack', '--quiet', '--extract-to', path, self.archive)
			subprocess.run(cmd, check=True)

			assert len(os.listdir(path)) == 1, "All files should be inside a directory"
			self.path_unpacked = os.path.join(path, self.ctan_name)

			cmd = ('pkgcheck', '-d', self.path_unpacked)
			subprocess.run(cmd, check=False)
		
			self.check_version(self.path_unpacked, self.ctan_name)
			self.check_filelist(self.path_unpacked)
			self.build_documentation()


	# --------- internal check functions ---------

	def check_version(self, path, ctan_name):
		date = datetime.date.today()
		tags = self.git_tag_list_version()
		assert tags, "Current version has no version tag"
		assert len(tags) == 1, "Too many version tags for this commit: %s" % ", ".join(tags)
		version = tags[0]

		dtx_date, dtx_version = self.read_dtx_version(path, ctan_name)
		if dtx_date != date:
			print("WARNING: the date specified in the dtx file is not today but %s" % dtx_date)

		if dtx_version is None:
			print("WARNING: No version specified in dtx file")
		else:
			assert dtx_version == version, "Version specified in dtx file %r does not match version tag %r" % (dtx_version, version)

		doc_date, doc_version = self.read_doc_version(path, ctan_name)
		assert doc_date == dtx_date, "Date specified in documentation %s does not match dtx file %s" % (doc_date, dtx_date)
		if doc_version is None:
			print("WARNING: No version specification found in the documentation")
		else:
			assert doc_version == dtx_version, "Version specified in the documentation %r does not match dtx file %r" % (doc_version, dtx_version)

	def check_filelist(self, path):
		'''
		The LPPL requires a list of all files which the work consists of.
		This function looks for a separate file listing all these files
		and whether these files are contained in the exported archive
		and whether exported files are missing in the list.
		If you have very few files and list these files in the header of each file
		instead of providing a separate file containing the file list
		this function will print the warning "no file list found".
		In that case please check this manually.
		'''
		reo = re.compile(r'(file.*list|manifest)\.txt', re.I)
		fns = os.listdir(path)
		fns = [fn for fn in fns if reo.search(fn)]
		n = len(fns)
		if n == 0:
			print("WARNING: no file list found")
			return
		elif n > 1:
			assert False, "found several files which might be a file list: %s" % ', '.join(fns)
		fn_filelist = os.path.join(path, fns[0])

		existing_files = set()
		for parent, dirs, files in os.walk(path):
			for fn in files:
				fn = os.path.join(parent, fn)
				fn = os.path.relpath(fn, path)
				existing_files.add(fn)

		expected_files = set()
		reo = re.compile('(- )?(?P<fn>[\w./-]+)(\s+\W.*)?$')
		with open(fn_filelist, 'rt') as f:
			for ln in f:
				m = reo.match(ln)
				if m:
					fn = m.group('fn')
					if os.path.splitext(fn)[1] == '.sty':
						continue
					expected_files.add(fn)

		missing_files = expected_files - existing_files
		unexpected_files = existing_files - expected_files
		error = False
		if unexpected_files:
			error = True
			print("files not covered by license:")
			for fn in unexpected_files:
				print("- %s" % fn)
		if missing_files:
			error = True
			print("missing files:")
			for fn in missing_files:
				print("- %s" % fn)
		if error:
			assert False, "file list does not match exported files (see above)"

	def build_documentation(self):
		print("trying to build documentation ...")
		ffn = self.ffn_doc
		ui = self.DocUI()
		Controller([ffn], ui=ui, max_retries=0).test_all()
		self.run_biber(ffn)
		Controller([ffn], ui=ui).test_all()
		if ui.issues:
			for i in ui.issues:
				print(i.msg)
			assert False, "failed to build documentation"

	def run_biber(self, ffn):
		arg = os.path.splitext(ffn)[0]
		out = subprocess.run(['biber', arg], check=True, stdout=subprocess.PIPE, encoding=shell_encoding).stdout
		failed = False
		for ln in out:
			if "ERROR" in ln or "WARN" in ln:
				print(ln)
				failed = True
		assert not failed

	class DocUI:

		def test_start(self, tex_filename, retry=0):
			self.failed = False
			self.issues = list()

		def unexpected(self, issue):
			assert not issue.expected
			self.issues.append(issue)
			self.failed = True

		def missing(self, issue):
			assert issue.expected
			self.issues.append(issue)
			self.failed = True

		def test_end(self, error=None):
			if error:
				raise error


	# --------- extract data from git ---------

	def git_status(self):
		cmd = ["git", "status", "--porcelain=v1"]
		status = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, encoding=shell_encoding, cwd=self.path_to_be_exported).stdout.splitlines()

		untracked = False
		unstaged = False
		staged = False

		# ln[0] = X = index
		# ln[1] = Y = work tree
		for ln in status:
			if ln[0] not in ' !?':
				staged = True
			if ln[1] not in ' !?':
				unstaged = True
			if ln[:2] == '??':
				untracked = True

		return staged or unstaged, untracked

	def git_tag_list_version(self):
		cmd = ["git", "tag", "--list", "v*", "--points-at", "HEAD"]
		tags = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, encoding=shell_encoding, cwd=self.path_to_be_exported).stdout.splitlines()
		return tags


	# --------- extract data from files ---------

	def read_dtx_version(self, path, ctan_name):
		ffn = os.path.join(path, ctan_name + '.dtx')
		reo = re.compile(r'\\ProvidesPackage\{.*\}\[(?P<version>.*?)\]')
		with open(ffn, 'rt') as f:
			for ln in f:
				m = reo.match(ln)
				if m:
					version = m.group("version")
					version = version.split(maxsplit=3)
					n = len(version)
					if n == 1:
						date    = version[0]
						version = None
						comment = None
					elif n == 2:
						date    = version[0]
						version = version[1]
						comment = None
					elif n == 3:
						date    = version[0]
						version = version[1]
						comment = version[2]
					else:
						assert False

					date = datetime.datetime.strptime(date, "%Y/%m/%d").date()
					return date, version

		assert False, "No version specified in %s file" % ffn

	def read_doc_version(self, path, ctan_name):
		possible_file_names = (
			os.path.join(path, ctan_name+'.dtx'),
			os.path.join(path, ctan_name+'-doc.tex'),
			os.path.join(path, 'doc', ctan_name+'.tex'),
		)
		searched_files = []
		for ffn in possible_file_names:
			if not os.path.isfile(ffn):
				continue
			date, version = self.read_doc_version_from_file(ffn)
			if date is not None:
				self.ffn_doc = ffn
				return date, version

			searched_files.append(ffn)

		assert False, "No documentation version found, searched files: %s" % ", ".join(searched_files)

	def read_doc_version_from_file(self, ffn):
		reo_date = re.compile(r'\\date\{(.*?)\}')
		reo_version = re.compile(r'\\version\{(.*?)\}')
		date = None
		version = None
		with open(ffn, 'rt') as f:
			for ln in f:
				if date is None:
					m = reo_date.search(ln)
					if m:
						date = m.group(1)
						date = self.parse_doc_date(date)
				elif version is None:
					m = reo_version.search(ln)
					if m:
						version = m.group(1)
				else:
					break

		return date, version

	def parse_doc_date(self, date):
		possible_patterns = (
			'%d.%m.%Y',
			'%d %B %Y',
			'%d~%B %Y',
			'%B %d, %Y',
			'%B~%d, %Y',
			'%Y-%m-%d',
			'%Y/%m/%d',
		)
		for pattern in possible_patterns:
			try:
				return datetime.datetime.strptime(date, pattern).date()
			except ValueError:
				continue

		assert False, "Failed to parse documentation date: %r" % date


if __name__ == '__main__':
	import argparse
	__doc__ += """
	MagicCommentExtractor.allowed_programs = {allowed_programs!r}
	MagicCommentExtractor.allowed_options = {allowed_options!r}
	MagicCommentExtractor.program = {program!r}
	""".replace("\t", "").format(**MagicCommentExtractor.__dict__)
	p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	for test_dir in dirs_test:
		if os.path.isdir(test_dir):
			default_paths = [test_dir]
			break
	else:
		default_paths = []
	p.add_argument('paths', nargs='*', default=default_paths, help=
			"If a path is a directory instead of a file all TeX files inside of that directory are tested. "
			"Subdirectories are ignored. "
			"If no paths are given: If a directory called 'test' exists in the current working directory it is used, "
			"otherwise the current working directory is used.")
	p.add_argument('-b', '--batch', metavar='PATH', help="An ins or dtx file which I execute with tex (in the directory where the file is located) in order to (re)generate the sty file. Use a minus to skip this.")
	p.add_argument('-c', '--ctan', metavar='PATH', nargs='?', const='', help="create a zip file for CTAN upload and test it with pkgcheck")
	p.add_argument('--skip-tests', action='store_true', help="skip running the tests specified by <paths> for faster testing of --ctan export")

	args = p.parse_args()

	# if argument to --ctan exists and no path argument has been given
	# use --ctan argument for the path argument, too
	if args.ctan and args.paths is default_paths:
		if os.path.isdir(args.ctan):
			root = args.ctan
		elif os.path.isfile(args.ctan):
			root = os.path.split(args.ctan)[0]
		else:
			root = None
		if root:
			args.paths = [p for p in map(lambda p: os.path.join(root, p), dirs_test) if os.path.isdir(p)][:1]
			dirs_ins = [p for p in map(lambda p: os.path.join(root, p), dirs_ins) if os.path.isdir(p)]
	elif args.paths is not default_paths and args.paths and not args.batch:
		root = args.paths[0]
		if os.path.isfile(root):
			root = os.path.split(root)[0]
		dirs_ins = [p for p in map(lambda p: os.path.join(root, p), dirs_ins) if os.path.isdir(p)]

	BATCH_NONE = '-'
	if args.batch != BATCH_NONE:
		if not args.batch:
			args.batch = find_ins_file()
		if args.batch:
			extract_sty(args.batch)

	if not args.skip_tests:
		c = Controller(args.paths)
		c.test_all()

	if args.ctan is not None:
		if not args.ctan and args.batch and args.batch != BATCH_NONE:
			args.ctan = os.path.split(args.batch)[0]
		ctan = CtanExport(args.ctan)
		try:
			ctan.create_archive()
			ctan.test_archive()
		except AssertionError as e:
			print("ERROR: %s" % e)
