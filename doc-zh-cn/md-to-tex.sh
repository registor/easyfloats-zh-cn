#!/usr/bin/env bash

fn=content.tex
dirout=content
fnlinks=links.tex

packages="float|caption|subcaption|graphicx|graphics|graphbox|pgfkeys|etoolbox|environ|placeins|flafter|booktabs|xcolor|array|siunitx|tabularx|longtable|hyperref|cleveref|biblatex|tikz|trivfloat|newfloat|capt-of|subfigure|subfig|geometry"
errormessages="Illegal pream-token|Missing number, treated as zero"

cp "easyfloats.md" "$fn"
texroot='../easyfloats.tex'
echo -n "" >"$fnlinks"
tmp="`mktemp`"

#Warning: sed has no non-greedy! => use perl instead
#https://stackoverflow.com/questions/1103149/non-greedy-reluctant-regex-matching-in-sed

# error message
sed -Ei '/```latex$/,/```$/! s/(error\s+(message\s+)?)"([^"]+)"/\1\\errormessage{\3}/gI' "$fn"
sed -Ei '/```latex$/,/```$/! s/"([^"]+)"(\s+error)/\\errormessage{\1}\2/gI' "$fn"
sed -Ei '/```latex$/,/```$/! s/"([^"]*'"($errormessages)"'[^"]*)"/\\errormessage{\1}/gI' "$fn"

# sections
sed -Ei 's/^# (.*)/\\section{\1}/' "$fn"
sed -Ei 's/^## (.*)/\\subsection{\1}/' "$fn"
sed -Ei 's/^### (.*)/\\subsubsection{\1}/' "$fn"
# replace \section{Abstract} by \begin{abstract} and remove following empty lines
sed -i '/\\section{Abstract}/,/./ {
	/^[^\\]/ {
		i \\\begin{abstract}
		b
	}
	d
}' "$fn"
# remove unneeded \section{Table of contents} and insert \end{abstract}
sed -i 's/\\section{Table of contents}/\\end{abstract}/' "$fn"
# remove empty lines before \end{abstract}
sed -Eni '/\\begin\{abstract\}/,/\\end\{abstract\}/ {
	: loop; s/^\s*$/&/; t empty; b nonempty
	: empty
		N; s/\\end\{abstract\}/&/; t end; b else
		: end;  s/^\s*\n//p; b
		: else; b loop
	: nonempty; p; b
}; p' "$fn"

# descriptions
sed -Ei 's/\\.*section\{`([^`]+)` environment\}/&\n\\DescribeEnv{\1}/' "$fn"
sed -Ei 's/\\.*section\{`([^`]+)` command\}/&\n\\DescribeMacro{\1}/' "$fn"
sed -Ei '/section\{Setting options globally\}/,$ s/^`(\\[a-z]+).*`/\\DescribeMacro{\1}\n&/I' "$fn"
sed -Ei '/section\{Hooks\}/,$ s/^- (`(\\[a-z]+).*`.*)/\n\\DescribeMacro{\2}\n\1/I' "$fn"
sed -Ei 's/<!--describe macro: (.*)-->/\\DescribeMacro{\1}/' "$fn"
sed -Ei '/section\{Help\}/,/\\(sub(sub)?)?section/ s/.*handler[^`]* `([^`]+)`.*/\\DescribeHandler{\1}\n&/I' "$fn"
sed -Ei '/section\{Help\}/,/\\(sub(sub)?)?section/ s/.*`([^`]+)` [^`]*handler.*/\\DescribeHandler{\1}\n&/I' "$fn"
sed -Ei '/section\{Help\}/,/\\(sub(sub)?)?section/ s/.*`([^`]+)` key.*/\\DescribeKey{\1}\n&/I' "$fn"
# delete duplicate \DescribeMacro
perl -i -ne '(!/\\DescribeMacro\{.*?\}/ || ! $x{$_}++) && print' "$fn"
# delete empty lines after \Describe*
sed -Ei '/\\Describe/,/^./ {/^$/ d}' "$fn"

# create labels for sections
sed -Ei '/section\{([^{}]+)\}/ {p; s/^[^{]+\{([^}]*)\}/\1/; s/\\|`//g; s/\W+/-/g; s/.*/\\label{\L&}/}' "$fn"
sed -En 's/^\\label\{([^}]*)\}/\1/p' "$fn" | sort | uniq -d | while IFS= read -r duplicatelabel; do
	awk '$0=="\\label{'"$duplicatelabel"'}" && ++count>=2{sub("}", "-"count"}")} 1' "$fn" > "$tmp"
	mv "$tmp" "$fn"
done

# table of contents
sed -Ei 's/\[\[_TOC_\]\]/\\tableofcontents/' "$fn"

# code
sed -Ei '/\\section\{Motivation\}/,/^\\section/{ /\s*<!--linenumbers-->/ {N; s/.*/\\begin{examplecode\\starred}{\\ExamplecodeNoBox\\ExamplecodeLinenumbers}/}}' "$fn"
sed -Ei '/\\section\{Motivation\}/,/^\\section/ s/^```latex/\\begin{examplecode\\starred}{}/' "$fn"
sed -Ei '/\\section\{Motivation\}/,/^\\section/ s/```latex/\\begin{examplecode\\starred}{\\ExamplecodeNoBox}/' "$fn"
sed -Ei '/\\section\{Motivation\}/,/^\\section/ s/```/\\end{examplecode\\starred}/' "$fn"
sed -Ei 's/```latex/\\begin{examplecode}/' "$fn"
sed -Ei 's/```/\\end{examplecode}/' "$fn"

# linebreaks
sed -i '/\\begin{examplecode/,/\\end{examplecode/! s/\\$/\\\\/' "$fn"

# quotes
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/"([^"]+)"/\\enquote{\1}/g' "$fn"

# itemize
for indentation in '' '  ' '   ' '     '; do
sed -Ei -n "/^$indentation- /{"'
	i \'"$indentation"'\\begin{itemize}
	p
	n
	:loop
	s/^\s*$/&/
	t emptyline
	s/^'"$indentation"'[- ]/&/
	t item
	i \'"$indentation"'\\end{itemize}
	x
	s/^[^\n]*\n//p
	s/.*//
	x
	p
	b

	:item
	x
	s/^[^\n]*\n//p
	s/.*//
	x
	p; n
	b loop

	:emptyline
	H
	n
	b loop
}; p' "$fn"
sed -Ei "s/^${indentation}- /${indentation}"'\\item /' "$fn"

sed -Ei -n "/^$indentation[1-9]+\) /{"'
	i \'"$indentation"'\\begin{enumerate}
	p
	n
	:loop
	s/^\s*$/&/
	t emptyline
	s/^'"$indentation"'([1-9]+\)| )/&/
	t item
	i \'"$indentation"'\\end{enumerate}
	x
	s/^[^\n]*\n//p
	s/.*//
	x
	p
	b

	:item
	x
	s/^[^\n]*\n//p
	s/.*//
	x
	p; n
	b loop

	:emptyline
	H
	n
	b loop
}; p' "$fn"
sed -Ei "s/^${indentation}[1-9]+\) /${indentation}"'\\item /' "$fn"
done
sed -Ei 's/\\item (Line[^:]*):/\\item[\1]/' "$fn"
sed -ni '/\\begin{itemize}/ {
	h; n
	s/\\item\[Line/&/; t description; b itemize
	: description; x; s/itemize/description/; p; x; p; b
	: itemize; x; p; x; p; b
}; p' "$fn"
sed -i '/\\item\[Line/,/\\end{itemize}/ s/\\end{itemize}/\\end{description}/' "$fn"

# key descriptions
# (I am putting them seperate so that I can make use of \end{itemize})
sed -Ei 's/^\\item `([^`]+)`\s*\(\[([^]]+ key[^]]*)\]\[\]\)\s*\/\s*`([^`]+)`\s*\(\[([^]]+ key)\]\[\]\)(:)?/\\keydoc{\1}{\2} \/\n\\keydoc{\3}{\4}\5/
         t keydoc; b
	 : keydoc; s/:$//; t descr; b nodescr
	 : nodescr; a
	 : descr' "$fn"
sed -Ei 's/^\\item `([^`]+)`\s*\(\[([^]]+ key[^]]*)\]\[\]\)(:)?/\\keydoc{\1}{\2}\3/
         t keydoc; b
	 : keydoc; s/:$//; t descr; b nodescr
	 : nodescr; a
	 : descr' "$fn"
sed -Ei '/they are all .*forwarding keys/ a \\\newcommand{\\TargetKey}[2]{/subobject/\\stripsubobject #2\\relax}%\n\\def\\stripsubobject subobject #1\\relax{\\stripoptplus{#1}}%' "$fn"
sed -Ei '/they are all .*forwarding keys/,/end\{itemize\}/ s/^\\item `(subobject [^`]+)`/\\forwardingkeydoc{\1}/' "$fn"
sed -Ei '/they are all .*forwarding keys/,/end\{itemize\}/ s!^\\item `((\s*[^`= ])+)(\s*=[^`]*)?`!\\forwardingkeydoc[target=/subobject/\1]{\1\3}!' "$fn"
sed -Ei '/section\{`subobject` environment\}/,/section\{/ s!^\\keydoc\{([^}]+)\}\{forwarding key\}!\\forwardingkeydoc[target=/object]{\1}!' "$fn"
sed -i  '/See \[section `object` environment./ a \\\newcommand{\\TargetKey}[2]{/object/#2}%' "$fn"
sed -Ei '/The following options correspond to those of an `object`/,/The following options are unique/ s!^\\keydoc\{([^}]+)\}\{([^}]+)\}!\\correspondingkeydoc{\1}{\2}!' "$fn"
# delete \begin{itemize} in front of \keydoc
sed -ni '/\\begin{itemize}/ {
	h; n; s/^\\\(forwarding\|corresponding\)\?keydoc/&/; t keydoc; b item
	: item; x; p; x;
	: keydoc; p;
	d
};p' "$fn"
# replace \end{itemize} after \keydoc by \endkeydoc
sed -i '/\\\(forwarding\|corresponding\)\?keydoc/,/\\begin{itemize}\|\\end{itemize}/ s/\\end{itemize}/\\endkeydoc/' "$fn"
# insert \keydocpath
sed -Ei 's/\\label\{(object|subobject|includegraphicobject)-(environment|command)\}/&\n\\begingroup\n\\keydocpath{\/\1}/' "$fn"
sed -Ei 's!^\\keydocpath\{/includegraphicobject\}$!\\keydocpath{/graphicobject}!' "$fn"
# insert \endgroup to limit \keydocpath
# note how the start label is outside of the filter
# if it was inside, the filter would not see the last line
# and it would go on for the rest of the file
sed -Eni ':start; /\\label\{(object|subobject|includegraphicobject)-(environment|command)\}/,/section\{/ {
		s/^\s*$/&/; t empty; s/section\{/&/; t end; b notend
		: empty;  H; n; b start
		: notend; x;s/[^\n]*\n//p;x;p;h; n; b start
		: end;    i \\\endgroup
		          x;s/[^\n]*\n//p;x;p;h; b
}; p' "$fn"

# package options
sed -Ei '/section.Package options/,/section\{/ {
	/^\\begin\{itemize\}/d
	s/^\\item `([^`]+)`:/\\pkgoptndoc{\1}/
	s/^\\end\{itemize\}/\\endpkgoptndoc/
}' "$fn"
sed -Eni '/\\pkgoptndoc/ {
	: start; s/\s+\(default\)//; t default; b loop
	: default; s/\\pkgoptndoc/\\pkgoptndoc\*/
	           p; d
	: loop; N; s/\s+\(default\)//; t default; s/\n.*\\pkgoptndoc/&/; t newdoc; s/\\endpkgoptndoc/&/; t end; b loop
	: newdoc;  h; s/\n[^\n]*$//; p; x; s/^.*\n//;
		# t is required to reset the successful substitution
		t start
		b start
	: end;
		p; d
}; p' "$fn"
sed -i 's/The options labeled as \*default\* are used if an option is neither enabled nor disabled explicitly./The keys with a~\\radioon\\ are active by default and the keys with a~\\radiooff\\ are inactive by default./' "$fn"

# references
perl -pi -e 's/\[`([^]]*?)` environment\]\(.*?\)/\\env{\1} environment/g' "$fn"
perl -pi -e 's/\[`([^]]*?)`\]\(#.*?environment\)/\\env{\1}/g' "$fn"
perl -pi -e 's/\[`([^]]*?)` command\]\(.*?\)/\\cmd{\1} command/g' "$fn"
perl -pi -e 's/\[`(\\[A-Za-z@]+)`\]\(.*?\)/\\cmd{\1}/g' "$fn"
perl -ne "print if s/^.*?\[($packages)( [^]]*)?\]\((.*?)\)"'/\\newurllink{\1}{\3}/g' "$fn" >>"$fnlinks"
perl -pi -e "s/\[($packages)( [^]]*documentation)\](\[.*?\]|\(.*?\))"'/\\pkg{\1}\2~\\autocite{\1}/g' "$fn"
perl -pi -e "s/\[($packages)( [^]]*)?\](\[.*?\]|\(.*?\))"'/\\pkg{\1}\2/g' "$fn"
for i in {1..2}; do
	sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/!'" s/([^]]|^)\[($packages)\]([^[({:]|$)"'/\1\\pkg{\2}\3/g' "$fn"
done
sed -Ei 's/\[`([^]`]+)`( package)\]\[[^]]+\]/\\pkg{\1}\2/g' "$fn"
perl -pi -e 's/\[([^]]*?)\]\([^#:]*?\)/\\filename{\1}/g' "$fn"
perl -pi -e 's/\[`(.*?)`\]\(#package-options\)/\\pkgoptn{\1}/g' "$fn"

sed -Ei 's/`(.+\.pdf)`/\\filename{\1}/' "$fn"

# key type descriptions
sed -Ei '/section.*Key types/,/^\\(sub)?(sub)?section/ s/^\\item\s*\*([^*]+)\*:/\\keytypedoc{\1}/' "$fn"
sed -Eni '/^\\begin\{itemize\}$/ {
	h; n; s/\\keytypedoc/\0/; t drop; b print
	: print; x; p; x; p; b
	: drop; p; b;
}; p' "$fn"
sed -i '/\\keytypedoc/,/\\end{itemize}/ s/\\end{itemize}/\\endkeytypedoc/' "$fn"

# package descriptions
sed -Ei '/section.*Used packages/,$ s/^\\item\s*\\pkg/\\pkgdoc/' "$fn"
sed -Ei 's.^(\\pkgdoc\{[^}]+\}\s*/\s*)\\pkg.\1\\pkgdoc.' "$fn"
sed -Eni '/^\\begin\{itemize\}$/ {
	h; n; s/\\pkgdoc/\0/; t drop; b print
	: print; x; p; x; p; b
	: drop; p; b;
}; p' "$fn"
sed -i '/\\pkgdoc/,/^\\end{itemize}/ s/^\\end{itemize}/\\endpkgdoc/' "$fn"

# licenses
sed -Ei 's/\[LaTeX Project Public License\]\([^)]+\)/\\license{lppl}/g' "$fn"
sed -Ei 's/\[WTFPL\]\([^)]+\)/\\license{wtfpl}/g' "$fn"

# links
link='\[((?:[^]]|`[^`]*`)+)\]'
perl -pi -e 's/'"$link"'\(#(.*?)\)/\\hyperref[\2]{\1}/g' "$fn"
perl -pi -e 's/'"$link"'\(([^#].*?)\)/\\href{\2}{\1}/g' "$fn"
perl -pi -e 's/'"$link"'\[\]/\\link{\1}/g' "$fn"
perl -pi -e 's/'"$link"'\[([a-z0-9_ ]+)\]/\\link[\2]{\1}/gi' "$fn"
sed -En 's/^\[([^]]*)\]: #(.+)$/\\newlabellink{\1}{\2}/p' "$fn" >>"$fnlinks"
sed -En 's/^\[([^]]*)\]: ([^#].*)$/\\newurllink{\1}{\2}/p' "$fn" >>"$fnlinks"
sed -Ei '/^\[([^]]*)\]:/d' "$fn"
perl -pi -e 's|((?<!{)\b[a-z]+://\S+)|\\url{\1}|g' "$fn"

sed -Ei 's/\\hyperref(\[[^]]+\])\{(`[^`]+`[^}]*)\}/\2/g' "$fn"

sed -Ei 's/\\link\{([^}]*key[^}]*)\}/\\keytype{\1}/g' "$fn"
sed -Ei 's/\\link\[([^]]*)\]\{([^}]*key[^}]*)\}/\\keytype[\1]{\2}/g' "$fn"

sed -Ei 's/^\\hyperref\[([^]]*)\]\{[^}]*\}/\\Cref{\1}/g' "$fn"
sed -Ei '/\\hyperref\[([^]]*)\]\{subobjects\}/! s/\\hyperref\[([^]]*)\]\{[^}]*\}/\\cref{\1}/g' "$fn"
sed -Ei 's/\\cref\{([^}]*)\} and \\cref\{([^}]*)\}/\\cref{\1,\2}/g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/(the )?\\href\{([^}]+)\}\{[^}]+\}/\\url{\2}/g' "$fn"

# rename link so that I can later replace TeX by \TeX
sed -Ei 's/(\\link)(\{TeX by Topic\})/\1[texbytopic]\2/g' "$fn"
sed -Ei 's/\{TeX by Topic\}/{texbytopic}/g' "$fnlinks"

sed -Ei 's/\s+\\link\[([^]]*)\]\{see here\}/~\\autocite{\1}/g' "$fn"
sed -Ei 's/The TeXbook,?\s*([A-Za-z]+ [0-9]+(\.[0-9]+)?)/\\mycite[\1]{texbook}/g' "$fn"
sed -Ei 's/\\link\[([^]]*)\]\{[^}]*\},?\s*([A-Za-z]+ [0-9]+(\.[0-9]+)?)/\\mycite[\2]{\1}/g' "$fn"
sed -Ei 's/\\link\{([^}]*)\},?\s*([A-Za-z]+ [0-9]+(\.[0-9]+)?)/\\mycite[\2]{\1}/g' "$fn"
sed -Ei 's/\\link\[([^]]*)\]\{(documentation)\}/\2~\\autocite{\1}/g' "$fn"
sed -Ei 's/\\link\[(texexchange[^]]*)\]\{[^}]*\}/\\autocite{\1}/g' "$fn"
sed -Ei 's/on \\autocite\{([^}]*)\}/in~\\autocite{\1}/g' "$fn"
sed -Ei 's/\\link\[([^]]*)\]\{[^}]*\}/\\mycite{\1}/g' "$fn"
sed -Ei 's/\\link\{(l2tabu)\}/\\mycite{\1}/g' "$fn"
sed -Ei 's/\(See (\\autocite\{[^}]*\})\.\)/\1/' "$fn"
sed -Ei 's/ \(see (section 2 \*The layout of formal tables\*)\)/~\\autocite[\1]{booktabs}/' "$fn"
sed -Ei 's/(cite(\[([^]]*)\])?)\{pgfkeys\}/\1{tikz}/g' "$fn"

sed -i 's/\\link{eTeX} /\\eTeX\\ /g' "$fn"
sed -i 's/\\link{eTeX}/\\eTeX/g' "$fn"
sed -Ei 's/\s+\\link\{([^}]*)\},?\s*([A-Za-z]+ [0-9]+(\.[0-9]+)?)/~\\autocite[\2]{\1}/g' "$fn"
sed -Ei 's/\s+\\link\{([^}]*)\}/~\\autocite{\1}/g' "$fn"
sed -Ei 's/\\enquote(\{[^}]*\})\s+\(\\mycite(\[[^]]*\]\{[^}]*\})\)/\\textcquote\2\1/g' "$fn"
sed -Ei 's/\\mycite(\[[^]\]*]\{latex2e\})/\\autocite\1/g' "$fn"
sed -Ei 's/\\link\{([^}]*)\}, (section \*[^*]*\*)/\\autocite[\2]{\1}/g' "$fn"
sed -Ei 's/\((\\autocite(\[[^]\]*])?\{[^}]*\})\)/\1/g' "$fn"

# special characters
# & is a special character in sed, therefore it must be escaped
# \ must be escaped as well, resulting in three \
sed -Ei 's/TikZ[  ]& Pgf/TikZ~\\\& PGF/gI' "$fn"
sed -Ei 's/ /~/g' "$fn"
sed -Ei 's/—/---/g' "$fn"

# names
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<TeX\>([^a-zA-Z ]|$)/\\TeX\1/g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<TeX\> /\\TeX\\ /g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<LaTeX2e([^a-zA-Z ]|$)/\\LaTeXe\1/g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<LaTeX2e\> /\\LaTeXe\\ /g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<LaTeX([^a-zA-Z ]|$)/\\LaTeX\1/g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<LaTeX\> /\\LaTeX\\ /g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<TikZ\>([^ ]|$)/\\TikZ\1/g' "$fn"
sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s/\<TikZ\> /\\TikZ\\ /g' "$fn"

# keydoc pattern examples
sed -i '/\\keydoc{graphic <option> =/ a \
\\keylinktarget{graphic width}' "$fn"
sed -i '/\\keydoc{<env> arg =/ a \
\\keylinktarget{(<env>) arg(s) (+)}\
\\keylinktarget{(<env>) arg(s)}\
\\keylinktarget{tabularx arg+}\
\\keylinktarget{tabularx arg}\
\\keylinktarget{\\detokenize{tabular* arg}}\
\\keylinktarget{tabular arg}\
\\NoDescribeKey{env arg}' "$fn"

# wild card links
sed -i '/\\label{styles}/ a \
\\DescribeMeta{style}\
\\DescribeMeta{styles}' "$fn"
sed -i '/\\label{style-groups}/ a \\\DescribeMeta{group}' "$fn"
sed -i '/type = <type>/ a \\\DescribeMeta{type}' "$fn"

# default value + intial value as options
python3 <<eof
import re
with open("$fn", "rt") as f:
	code = f.read()
code = re.sub(r"(\\\\keydoc)((?:[^\n]|\n+(?= ))*?) *Default value:\s*(\`[^\`\n]*\`|[^.\n]*)\.\n?", r"\1[default value=\3]\2", code)
code = re.sub(r"(\\\\keydoc)((?:[^\n]|\n+(?= ))*?) *Initial value:\s*(\`[^\`\n]*\`|[^.\n]*)\.\n?", r"\1[initial value=\3]\2", code)
code = re.sub(r"(\\\\keydoc\[[^]]*)\]\[(.*?\])", r"\1, \2", code)
code = re.sub(r"(\\\\keydoc)(\{[^\n]*/\n\\\\keydoc)(\[.*?\])", r"\1\3\2", code)
with open("$fn", "wt") as f:
	f.write(code)
eof

# no end of sentence space after abbreviations
sed -Ei 's/(i\.e\.|e\.g\.) /\1\\ /g' "$fn"

# section names
sed -Ei 's/\*(Handlers for Key Inspection|The layout of formal tables|The `\\DeclareCaptionSubType` command|ltxref.dtx)\*/\\sectionname{\1}/g' "$fn"
# fill optional argument of \autocite
sed -Ei 's/(\\autocite)(\{[^}]+\}),? ([A-Za-z]+~[0-9]+(\.[0-9]+)?(\.[0-9]+)?(\s+\\sectionname\{[^}]+\})?)/\1[\3]\2/g' "$fn"


# avoid amibuity
sed -Ei 's/`(caption)`/\\key{\1}/g' "$fn"
sed -Ei 's/`(graphicx)`/\\pkgoptn{\1}/g' "$fn"
sed -Ei 's/`(graphbox)`( package option)/\\pkgoptn{\1}\2/g' "$fn"
sed -Ei 's/`(longtable)`( environment)/\\env{\1}\2/g' "$fn"
sed -Ei 's/`(tabularx)`/\\env{\1}/g' "$fn"
sed -Ei 's/(value of this key to )`(longtable)`/\1\\val{\2}/g' "$fn"
sed -Ei 's/`(longtable)`( environment)/\\pkgoptn{\1}\2/g' "$fn"
sed -Ei 's/`(longtable)`(s)/\\env{\1}\2/g' "$fn"
sed -Ei 's/(package option )`(table)`/\1\\pkgoptn{\2}/g' "$fn"
sed -Ei 's/`(table)`/\\env{\1}/g' "$fn"
sed -Ei 's/`(tex .+\.ins)`/\\verb|\1|/' "$fn"

# \bigpar
sed -Ei 's/\s*----+/\\bigpar/' "$fn"

# optional line breaks
for i in {1..2}; do
	sed -Ei '/\\begin\{examplecode\}/,/\\end\{examplecode\}/! s:^((`[^`]+`|\{[^{}]*\}|\[[^][]*\]|[^][`{}])*)/(.):\1\\slash \3:g' "$fn"
done
sed -Ei 's:(\\(sub)?(sub)?section\{[^}]*) / ([^}]*\}):\1~\\slash\\ \4:g' "$fn"
sed -Ei 's/(\\[a-z]+doc\{[^}]+\}\s*)\\slash /\1\//g' "$fn"
# convert inline code to display code to avoid overfull hboxes
sed -Ei 's/`((list )?caption=[^,`]+,)\s*([^`]+)`\.?/\\begin{examplecodekey}\n   \t\1\n   \t\3\n   \\end{examplecodekey}/g' "$fn"
sed -Ei 's/\. (Thanks to )/.$\\\\$ \1/' "$fn"
sed -Eni '/\\begin\{examplecodekey\}/ {
	h; n
	: loop; s/\$\\\\\$/&/; t linebreak; s/\\end/&/; t end; b else
	: linebreak; H; n; b lbloop
	: else; H; n; b loop
	: end; x; p; x; p; b
	: lbloop; s/\\end/&/; t lbend; b lbelse
	: lbelse; H; n; b lbloop
	: lbend
		H; x
		s/\\begin\{examplecodekey\}/\\begin{examplecodekey\\starred}{\\ExamplecodeEscapeinside $ $}/
		s/\\end\{examplecodekey\}/\\end{examplecodekey\\starred}/
		p; b
}; p' "$fn"

# titlepage
sed -i '/\\begin{abstract}/ {
	i \\\maketitle
	i \\\thispagestyle{empty}
	i \\\vfill
}' "$fn"
sed -i '/\\end{abstract}/ {
	a \\\vfill
	a \\\vspace{20em}
	a \\\url{https://gitlab.com/erzo/latex-easyfloats}
	a \\\clearpage
}' "$fn"

sed -i '/\\tableofcontents/ a \\\pagebreak' "$fn"

# section introduction Examples
cat >"$tmp" <<-'eof'

	Let's start with a few examples.
	Environments, commands and keys defined by this package are links (both in the code and in the text).
	Klicking on them will get you to their explanation in \cref{documentation}.
	
	\Cref{motivation} gives a motivation why this package is useful.
	There is a list of related packages in \cref{used-packages,other-packages}.
	Package names link to the rather short description in that list.

eof
sed -i '/\\label{examples}/ r '"$tmp" "$fn"
cat >"$tmp" <<-'eof'

	This section contains a list of other packages.
	The package names listed in this section link to their documentation on CTAN.
eof
sed -i '/\\label{references}/ r '"$tmp" "$fn"

sed -Ei 's/\s*\(?a question mark after the equals sign symbolizes that the value is optional\.?\)?//I' "$fn"

# footnotes
sed -Ei 's/^\((Actually[^)]+)\)/\\unskip\\footnote{\1}/' "$fn"
cat >"$tmp" <<-'eof'
/  is in \\LaTeX2 (somewhat simplified) equivalent to/ {
	i \  is in \\LaTeX2\\footnote{This will change in \\LaTeX3~\\autocite{ltx3env}.}
	i \  \\makeatletter
	i \  (somewhat simplified\\footnote{`\\begin` checks that it's argument is defined, `\\end` checks that it's argument matches that of `\\begin` and deals with `\\ignorespacesafterend` and `\\@endparenv`. Since 2019/10/01 `\\begin` and `\\end` are robust. Since 2020/10/01 they include hooks. \\autocite[section \\sectionname{ltmiscen.dtx}]{source2e}})
	i \  \\makeatother
	i \  equivalent to
	d
}
eof
sed -i -f "$tmp" "$fn"
rm "$tmp"


# split into seperate files and insert magic comments
[ -d "$dirout" ] || mkdir "$dirout"
function removetrailinglines {
	# \section command are duplicated, the first line of the next file is the last line of the current file.
	# This function removes this last line, the duplicated \section command and empty lines in front of it.
	sed -Eni '
		p; n;
		: loop; s/^\s*$/&/; t empty; s/^\\section//; t last; b else
		: empty; H; n; b loop
		: last; d
		: else; x; s/^[^\n]*\n//p; x; p; h; n; b loop
	' "$1"
}
function insertmagiccomment {
	sed -Ei '1i % !TeX root = '"$texroot"'\n' "$1"
}
sed -En 's/^\\section\{([^}]+)\}/\1/p' "$fn" | while IFS= read -r sec; do
	newfn="`echo "$sec" | sed -E 's/.*/\l&.tex/; s/ /-/g;'`"
	newfn="$dirout/$newfn"
	sed -n '/\\section{'"$sec"'}/,/^\\section/ p' "$fn" > "$newfn"
	removetrailinglines "$newfn"
	insertmagiccomment "$newfn"
	echo "\\input{${newfn%.tex}}"
done
newfn="titlepage.tex"
newfn="$dirout/$newfn"
sed -n '1,/^\\section/ p' "$fn" > "$newfn"
removetrailinglines "$newfn"
insertmagiccomment "$newfn"
rm "$fn"
