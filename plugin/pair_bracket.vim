vim9script
# Author:  Iranoan <iranoan+vim@gmail.com>
# License: GPL Ver.3.

scriptencoding utf-8

if exists('g:pair_bracket')
	finish
endif
g:pair_bracket = 1

pair_bracket#Init()
