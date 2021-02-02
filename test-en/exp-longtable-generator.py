#!/usr/bin/env python

import math

indentation = "\t"

power = 1

for angle in range(0,91,5):
	x = math.radians(angle)
	tan = math.tan(x) ** power
	sin = math.sin(x) ** power
	cos = math.cos(x) ** power
	if angle % 180 == 90:
		tan = r"\pminfty"
	else:
		tan = "%6.2f" % tan

	print(indentation + r"%3d  &  %5.2f & %5.2f & %s \\" % (angle, sin, cos, tan))
	if angle % 90 == 0 and angle % 360 != 0:
		print(indentation + r"\addlinespace")
