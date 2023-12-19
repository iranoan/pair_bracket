vim9script
# Author:  Iranoan <iranoan+vim@gmail.com>
# License: GPL Ver.3.

scriptencoding utf-8

var BackCursor = (): string => # カーソルを戻す (閉じ括弧入力後に間に入れるときなど)
	mode(1) =~# '^c' ? "\<Left>" :
	&rightleft ? "\<C-G>U\<Right>" : "\<C-G>U\<Left>"
var ForwardCursor = (): string => # カーソルを進める (閉じ括弧のタイプですでにその閉じ括弧が有った時など)
	mode(1) =~# '^c' ? "\<Right>" :
	&rightleft ? "\<C-G>U\<Left>" : "\<C-G>U\<Right>"

export def Init(): void
	var type_map: dict<list<string>>
	var c_flag: number
	var s_flag: bool

	def SetMap(s: string, f: string, b: string): void # 全て、もしくはバッファにキーマップ
		var lhs = substitute(s, '|', '<Bar>', 'g')
		var rhs = substitute(substitute(s, '''', '''''', 'g'), '|', '\\|', 'g')
		execute 'inoremap ' .. b .. '<expr> ' .. lhs .. ' <SID>' .. f .. '(''' .. rhs .. ''')'
		if c_flag || s_flag
			execute 'cnoremap ' .. b .. '<expr> ' .. lhs .. ' <SID>' .. f .. '(''' .. rhs .. ''')'
		endif
	enddef

	def SetAuCmdMap(s: string, f: string, d: dict<any>): void # FileType 様にキーマップを辞書に追加
		var lhs = substitute(s, '|', '<Bar>', 'g')
		var rhs = substitute(substitute(s, '''', '''''', 'g'), '|', '\\|', 'g')
		var ftypes = join(d.type, ',')
		if index(d.type, &filetype) != -1 # カレント・バッファに対するキーマップ
			SetMap(s, f, '<buffer>')
		endif
		if !has_key(type_map, ftypes)
			type_map[ftypes] = []
		endif
		add(type_map[ftypes], ' inoremap <buffer><expr> ' .. lhs .. ' <SID>' .. f .. '(''' .. rhs .. ''')')
		if c_flag || s_flag
			add(type_map[ftypes], ' cnoremap <buffer><expr> ' .. lhs .. ' <SID>' .. f .. '(''' .. rhs .. ''')')
		endif
	enddef

	def SetBracket(s: string, d: dict<any>): void
		c_flag = get(d, 'cmap', 1)
		s_flag = (get(d, 'search', {}) != {})
		if has_key(d, 'type')
			SetAuCmdMap(s, 'InputBra', d)
			SetAuCmdMap(d.pair, 'InputCket', d)
		else
			SetMap(s, 'InputBra', '')
			SetMap(d.pair, 'InputCket', '')
		endif
	enddef

	def SetQuote(s: string, d: dict<any>): void
		c_flag = get(d, 'cmap', 1)
		if has_key(d, 'type')
			SetAuCmdMap(s, 'Quote', d)
		else
			SetMap(s, 'Quote', '')
		endif
	enddef

	g:pairbracket = get(g:, 'pairbracket', {
		'(': {'pair': ')', 'space': 1, 'escape': {'vim': 1},
			'search': {'v\': 0, '\': 2, 'v': 1, '_': 0}},
		'[': {'pair': ']', 'space': 1, 'escape': {'vim': 1},
			'search': {'v\': 0, '\': 0, 'v': 1, '_': 1}},
		'{': {'pair': '}', 'space': 1, 'escape': {'vim': 1},
			'search': {'v\': 0, '\': 1, 'v': 1, '_': 0}},
		})
	g:pairquote = get(g:, 'pairquote', {
		'"': {},
		"'": {'escape_char': {'vim': "'"}},
		'`': {}
		})
	for [k, v] in items(g:pairbracket)
		SetBracket(k, v)
	endfor
	for [k, v] in items(g:pairquote)
		SetQuote(k, v)
	endfor
	if !empty(type_map)
		augroup PairBracket
			autocmd!
			for [k, v] in items(type_map)
				for m in v
					execute 'autocmd FileType ' .. k .. m
				endfor
			endfor
		augroup END
	endif
	inoremap <expr> <BS>    <SID>BS()
	cnoremap <expr> <BS>    <SID>BS()
	inoremap <expr> <CR>    <SID>CR()
	inoremap <expr> <Space> <SID>Space()
	# cnoremap <expr> <Space> <SID>Space() :cabbrev の区切りも空白なので、一切使えなくなる
	defcompile # これがないと最初に使われるのがコマンドラインの時に無駄な改行 (echo '' のような振る舞い) が発生する←Patch 9.0.1130 で修正
enddef

def SeparateLine(): list<string> # カーソル行のカーソルより前/後で文字列を分ける
	var column: number
	var line: string

	if mode(1) =~# '^c'
		column = getcmdpos()
		line = getcmdline()
	else
		column = col('.')
		line = getline('.')
	endif
	return [strpart(line, 0, column - 1), strpart(line, column - 1)]
enddef

def MatchBraCket(line1: string, line2: string, bra: string, cket: string, dic: dict<any>): list<number>
	# 未対応の括弧の数
	var cket_pos: number
	var bra_pos: number
	var pline: string = DeleteEscaped(line1, bra, dic)
	var nline: string = DeleteEscaped(line2, cket, dic)

	while true # 開き括弧より前に有る閉じ括弧を除く
		cket_pos = stridx(pline, cket)
		if cket_pos == -1
			break
		endif
		bra_pos = stridx(pline, bra)
		if bra_pos == -1 || cket_pos < bra_pos
			pline = strpart(pline, cket_pos + strlen(bra))
		else
			break
		endif
	endwhile
	return [count(pline, bra) - count(pline, cket), # カーソルより前に有る対応する括弧のない開き括弧の数
		count(nline, cket) - count(nline, bra)] # カーソルより後に有る対応する括弧のない閉じ括弧の数
enddef

def DeleteEscaped(l: string, s: string, dic: dict<any>): string # s でエスケープされた l を削除
	var escape_c: string

	if getcmdtype() ==# ':' || getcmdwintype() ==# ':'
		escape_c = get(dic, 'escape_char', {'vim': '\'})['vim']
	else
		escape_c = get(dic, 'escape_char', {})->get(&filetype, '\')
	endif
	if escape_c ==# '\'
		return substitute(substitute(l, '\\\\', '', 'g'), '\\' .. escape(s, '.$*~\[]'), '', 'g')
	else
		return substitute(substitute(l, escape(escape_c .. escape_c, '.$*~\[]'), '', 'g'), escape(escape_c .. s, '.$*~\[]'), '', 'g')
	endif
enddef

def GetMode(s: string, k: string, d: dict<any>): number # 検索モード、通常のコマンドライン、入力モードのペア括弧の入力方法を返す
	var escape: bool = (strlen(matchstr(s, '\\\+$')) % 2 == 1) # 直前が \ でエスケープされている

	def Search(str: string): number
		if k ==# '(' && (strlen(matchstr(s, '\\\+\ze%$')) % 2) # vim の正規表現 \%(\)
			return 2
		elseif match(str, '\\v') == -1
			if escape
				return get(d, 'search', {'\': 0})['\']
			else
				return get(d, 'search', {'_': 0})['_']
			endif
		else
			if escape
				return get(d, 'search', {'v\': 0})['v\']
			else
				return get(d, 'search', {'v': 0})['v']
			endif
		endif
	enddef

	var IsEscaped = (ftype: string): number => # 直前がエスケープされているか? ftype (&filetype 相当) によって入力モードを返す
		escape ? get(d, 'escape', {})->get(ftype, 0)
		: 1 # エスケープもされていない→標準のペア入力

	def Command(org: string): number # コマンドライン、コマンドラインウィンドウの時検索の文字列か? を調べ、その場合はそれに適したモードを返す
		# 検索文字列でないときは &filetype == 'vim' 用のモードを返す
		var str: string
		var match_range: list<number> = [-1, -1] # /.../, ?...? の {range} の(終了記号なし) 、->substitute() 等メソッド、substitute() 等関数やsubstitute 等コマンドの開始/終了位置

		def DeleteRangeString(): string # org から {range} を「.」に、文字列は「W」に、:s/{pattern}/{string}/ は「 」(空白) 置き換えた文字列を返す
			# 検索に関係ない部分を取り除く
			var r_slash: string      # /.../ の {range} の文字列
			var r_slash_s: number    # /.../ の {range} の開始位置
			var r_slash_e: number    # /.../ の {range} の終了位置
			var r_question: string   # ?...? の {range} の文字列
			var r_question_s: number # ?...? の {range} の開始位置
			var r_question_e: number # ?...? の {range} の終了位置
			var s_quot: string       # '...' の文字列
			var s_quot_s: number     # '...' の文字列開始位置
			var s_quot_e: number     # '...' の文字列終了位置
			var s_dquot: string      # "..." の文字列
			var s_dquot_s: number    # "..." の文字列開始位置
			var s_dquot_e: number    # "..." の文字列終了位置
			var replace: string      # s/{pattern}/{string}[/[flag]] の文字列
			var replace_s: number    # s/{pattern}/{string}[/[flag]]の文字列開始位置
			var replace_e: number    # s/{pattern}/{string}[/[flag]] の文字列終了位置
			var line: string = substitute(org, '\d\+', ' & ', 'g') # 数値が単語の区切りにならないので前後に空白付加

			def MatchSubstitute(): list<any> # :s/{pattern}/{string}[/[flag]] の範囲
				var command: string
				var search_s: string
				var match_s: string
				var bgn_s: number
				var goal_s: number
				var rep_s: string
				var match_r: string
				var bgn_r: number
				var goal_r: number

				for sep in '/?' # 検索による {range} と重なるのは /, ? 飲みなので、この 2 種のみ削除
					search_s = sep .. '\%(\\' .. sep .. '\|[^' .. sep .. ']\)*'
					rep_s = '\%(^\s*\|*:\s*\%(\d\+\|[.$%]\|\\[?&/]\|''[A-Za-z<>]\)*\s*\)s\%[ubstitute]' .. search_s .. search_s .. '\%(' .. sep .. '[geciInp#lr]*\)\?'
					[match_r, bgn_r, goal_r] = matchstrpos(line, rep_s)
					if bgn_r == -1
						continue
					endif
					search_s = '\%(^\s*\|*:\s*\%(\d\+\|[.$%]\|\\[?&/]\|''[A-Za-z<>]\)*\s*\)s\%[ubstitute]' .. search_s
					[match_s, bgn_s, goal_s] = matchstrpos(line, search_s)
					if match_r != match_s # s/a\/a\(a\)aa\/aaa/replace と置換文字列まであれば、検索部分だけのヒット範囲が異なる
						return [match_r, bgn_r, goal_r]
					elseif match_r[-2 : -1] == '\' .. sep # たとえ同じであっても s/a\/a\(a\)aa\/aaa\/ とエスケープされた / の時は検索文字列の入力の続き
						&& strlen(matchstr(match_r, '\\\+\ze' .. sep .. '$')) % 2
						return [match_r, bgn_r, goal_r]
					endif
				endfor
				return ['', -1, -1]
			enddef

			def Match(search_string: string): list<any>
				var ss: string
				var b: number
				var e: number

				[ss, b, e] = matchstrpos(line, search_string)
				if b != -1 && strlen(matchstr(ss, '\\\+$')) % 2
					return [ss, b, e]
				endif
				return ['', -1, -1]
			enddef

			while true
				[r_slash, r_slash_s, r_slash_e] = Match('\/\%(\\/\|[^/]\)\+\/')
				[r_question, r_question_s, r_question_e] = Match('?\%(\\?\|[^?]\)\+?')
				[s_quot, s_quot_s, s_quot_e] = Match('"\%(\\"\|[^"]\)\+"')
				[s_dquot, s_dquot_s, s_dquot_e] = Match('''\%(''''\|[^'']\)\+''')
				[replace, replace_s, replace_e] = MatchSubstitute()
				# 検索で最も前でマッチし部分のみ置き換える
				if r_slash_s != -1
					&& ( r_question_s == -1 || r_slash_s < r_question_s )
					&& ( s_quot_s == -1     || r_slash_s < s_quot_s )
					&& ( s_dquot_s == -1    || r_slash_s < s_dquot_s )
					&& ( replace_s == -1    || r_slash_s < replace_s )
					line = substitute(line, '\%(\s*:\s*\)\?' .. escape(r_slash, '.$*~\[]') .. '\%(\s*[-+]\s*\d\+\s*\)\?,\?', '.', '')
				elseif r_question_s != -1
					&& ( r_slash_s == -1    || r_question_s < r_slash_s )
					&& ( s_quot_s == -1     || r_question_s < s_quot_s )
					&& ( s_dquot_s == -1    || r_question_s < s_dquot_s )
					&& ( replace_s == -1    || r_question_s < replace_s )
					line = substitute(line, '\%(\s*:\s*\)\?' .. escape(r_question, '.$*~\[]') .. '\%(\s*[-+]\s*\d\+\s*\)\?,\?', '.', '')
				elseif s_quot_s != -1
					&& ( r_slash_s == -1    || s_quot_s < r_slash_s )
					&& ( r_question_s == -1 || s_quot_s < r_question_s )
					&& ( s_dquot_s == -1    || s_quot_s < s_dquot_s )
					&& ( replace_s == -1    || s_quot_s < replace_s )
					line = substitute(line, escape(s_quot, '.$*~\[]'), 'W', '')
				elseif s_dquot_s != -1
					&& ( r_slash_s == -1    || s_dquot_s < r_slash_s )
					&& ( r_question_s == -1 || s_dquot_s < r_question_s )
					&& ( s_quot_s == -1     || s_dquot_s < s_quot_s )
					&& ( replace_s == -1    || s_dquot_s < replace_s )
					line = substitute(line, escape(s_dquot, '.$*~\[]'), 'W', '')
				elseif replace_s != -1
					&& ( r_slash_s == -1    || replace_s < r_slash_s )
					&& ( r_question_s == -1 || replace_s < r_question_s )
					&& ( s_quot_s == -1     || replace_s < s_quot_s )
					&& ( s_dquot_s == -1    || replace_s < s_dquot_s )
					line = substitute(line, escape(replace, '.$*~\[]'), ' ', '')
				else
					break
				endif
			endwhile
			return line
		enddef

		def CheckStart(match_r: list<number>): list<number> # マッチした範囲が、既存のマッチ範囲より前から始まるか調べ、そうであるなら新たな範囲として返す
			# 開始位置が同じなら、終了位置が後ろの側
			if match_range[0] == -1
				return match_r
			elseif ( match_r[0] != -1 ) && ( match_range[0] > match_r[0] || ( match_range[0] == match_r[0] && match_range[1] < match_r[1] ) )
				return match_r
			endif
			return match_range
		enddef

		def MatchStr(pat: string): list<number> # matchstrpo() に似ているが、既存のマッチ範囲より前から始まっているときのみデータを書き換える
			var tmp_s: string
			var bgn: number
			var goal: number

			[tmp_s, bgn, goal] = matchstrpos(str, pat)
			return CheckStart([bgn, goal])
		enddef

		def MatchCommand(com: string, sep: string): list<number> # 検索に関係するコマンドがあるか調べる
			var tmp_s: string
			var bgn: number
			var goal: number
			var command: string = '\zs\%(^\s*\|*:\s*\%(\d\+\|[.$%]\|\\[?&/]\|''[A-Za-z<>]\)*\s*\)'
			var escaped_sep: string = escape(sep, '/.$*~\[]')
			# var escaped_sep1: string = escape(sep, '/')

			[tmp_s, bgn, goal] = matchstrpos(str, command .. escaped_sep .. '\ze\%(\\' .. sep .. '\|[^' .. sep .. ']\)*$')
			# [tmp_s, bgn, goal] = matchstrpos(str, command .. escaped_sep .. '\ze\%(\\' .. escaped_sep .. '\|[^' .. escaped_sep1 .. ']\)*$')
			return CheckStart([bgn, goal])
		enddef

		def MatchFunc(): bool # 検索に関係する関数を探す
			# マッチ範囲を書き換え、かつ直前が -> method の時は false を返す
			# ->substitute(arg, ... 等となっていて検索部分がすでに入力済み
			var beg_end: list<number>

			beg_end = MatchStr('\zs\<\%(substitute\|match\%(end\|str\|strpos\|list\)\?\)(\s*\w\+\s*,\s*"\ze\%(\\"\|[^"]\)*\C$')
			if beg_end[0] != -1
				match_range = CheckStart(beg_end)
				if match_range != beg_end
					return true
				elseif beg_end[0] != match(str, '->\zs\%(substitute\|match\%(end\|str\|strpos\|list\)\?\)(\s*\w\+\s*,\s*"\ze\%(\\"\|[^"]\)*\C$')
					return true
				endif
				return false
			endif
			beg_end = MatchStr('\zs\<\%(substitute\|match\%(end\|str\|strpos\|list\)\?\)(\s*\w\+\s*,\s*''\ze\%(''''\|[^'']\)*\C$')
			if beg_end[0] != -1
				match_range = CheckStart(beg_end)
				if match_range != beg_end
					return true
				elseif beg_end[0] != match(str, '->\zs\%(substitute\|match\%(end\|str\|strpos\|list\)\?\)(\s*\w\+\s*,\s*''\ze\%(''''\|[^'']\)*\C$')
					# メソッドではない
					return true
				endif
				# メソッドの時は検索文字列は1つ目の引数
				return false
			endif
			return true
		enddef

		str = DeleteRangeString()
		match_range = MatchStr('\zs/\ze\%(\\/\|[^/]\)*$')
		match_range = MatchStr('\zs?\ze\%(\\?\|[^?]\)*$')
		match_range = MatchStr('\zs->\%(substitute\|match\%(end\|str\|strpos\|list\)\?\)(\s*"\ze\%(\\"\|[^"]\)*\C$')
		match_range = MatchStr('\zs->\%(substitute\|match\%(end\|str\|strpos\|list\)\?\)(\s*''\ze\%(''''\|[^'']\)*\C$')
		for sep in '!"#$%&''()*+,-./:;<=>?@[]^_'
			match_range = MatchCommand('s\%[ubstitute]', sep)
		endfor
		match_range = MatchCommand('g\%[lobal]', '/')
		match_range = MatchCommand('g\%[lobal]!', '/')
		match_range = MatchCommand('v\%[global]', '/')
		if match_range[0] != -1 && MatchFunc()
			return Search(str)
		endif
		return IsEscaped('vim')
	enddef

	if getcmdtype() =~# '[/?]' || getcmdwintype() =~# '[/?]'
		return Search(s)
	elseif getcmdtype() ==# ':' || getcmdwintype() ==# ':' || &filetype == 'vim'
		return Command(s)
	endif
	return IsEscaped(&filetype)
enddef

def InputBra(str: string): string # 括弧などをペアで入力
	var pline: string     # カーソル前の内容
	var nline: string     # カーソル後の内容
	var prevMatch: number # カーソル前だけで対応する閉じ括弧のない開き括弧の数
	var nextMatch: number # カーソル後だけで対応する開き括弧のない閉じ括弧の数
	var pairStr: string   # 対応する閉じ括弧
	var move: string      # 入力後のカーソル移動を示すキー
	var pair_dic: dict<any> = g:pairbracket[str] # 開き括弧に関わる各種情報辞書
	var escape: number    # ペア括弧の入力方法

	if mode(1) =~# '^R'
		|| (!get(pair_dic, 'cmap', 1) && (getcmdtype() ==# ':' || getcmdwintype() ==# ':'))
		return str
	endif
	[pline, nline] = SeparateLine()
	escape = GetMode(pline, str, pair_dic)
	if escape == 2
		pairStr = '\' .. pair_dic.pair
	elseif escape
		pairStr = pair_dic.pair
	else
		return str
	endif
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, str, pairStr, pair_dic)
	if prevMatch >= nextMatch
		for i in range(strcharlen(pairStr))
			move ..= BackCursor()
		endfor
		return str .. pairStr .. move
	else
		return str
	endif
enddef

def InputCket(str: string): string # 閉じ括弧の入力、または入力の変わりに移動
	var pline: string
	var nline: string
	var prevMatch: number
	var nextMatch: number
	var pairStr: string
	var pair_dic: dict<any>

	if mode(1) =~# '^R'
		return str
	endif
	for [k, v] in items(g:pairbracket)
		if str ==# v.pair
			if !get(g:pairbracket[k], 'cmap', 1) && getcmdwintype() !=# ''
				return str
			endif
			pairStr = k
			pair_dic = v
			break
		endif
	endfor
	[pline, nline] = SeparateLine()
	if strlen(matchstr(pline, '\\\+$')) % 2 # 直前が \ でエスケープされている
		return str
	endif
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, pairStr, str, pair_dic)
	if match(nline, '^' .. escape(str, '.$*~\[]')) !=# -1 && prevMatch <= nextMatch
		return ForwardCursor()
	else
		return str
	endif
enddef

def Quote(str: string): string # クォーテーションの入力
	var pline: string
	var nline: string
	var prevChar: string
	var nextQuote: number
	var prevQuote: number
	var pair_dic: dict<any> = g:pairquote[str]

	def InPair(): string # ペアとなる引用符のを入力し間にカーソル移動
		var ret = str .. str

		for i in range(strcharlen(str))
			ret ..= BackCursor()
		endfor
		return ret
	enddef

	def IsOddQuote(l: string): number # 引用符の個数が奇数個か?
		return count(DeleteEscaped(l, str, pair_dic), str) % 2
	enddef

	def InPairNextPrev(p: string, n: string): string # 直前/直後に限らずカーソルより前 (p)/後 (n) の引用記号個数に応じて、ペア入力か否かを変える
		var is_prev_odd: number # カーソルより前に有る引用符が奇数個か?
		var is_next_odd: number # カーソルより前に有る引用符が奇数個か?

		is_prev_odd = IsOddQuote(p) # カーソルより前に有る引用符が奇数個か?
		is_next_odd = IsOddQuote(n) # カーソルより前に有る引用符が奇数個か?
		if is_prev_odd == is_next_odd
			return InPair()
		elseif is_prev_odd || is_next_odd # 前後両方奇数個なら上が該当しているので、どちらか一方のみ奇数個
			return str
		else
			return InPair()
		endif
	enddef

	if mode(1) =~# '^R'
		|| (!get(pair_dic, 'cmap', 1) && (getcmdtype() ==# ':' || getcmdwintype() ==# ':'))
		|| (!get(pair_dic, 'search', 0) && getcmdtype() =~# '[/?]' || getcmdwintype() =~# '/?:')
		return str
	endif
	[pline, nline] = SeparateLine()
	prevChar = matchstr(pline, '.$')
	nextQuote = strlen(matchstr(nline, '^' .. escape(str, '.$*~\[]') .. '\+'))
	prevQuote = strlen(matchstr(pline, escape(str, '.$*~\[]') .. '\+$'))
	if strlen(matchstr(pline, '\\\+$')) % 2 # 直前が \ でエスケープされている
		|| prevChar =~# '\a'                  # 直前が欧文数字
		|| prevChar =~# '\d'
		|| prevChar =~# '[À-öø-ƿǄ-ʯͲͳͶͷͻ-ͽͲͳͶͷͻ-ͽΌΎ-ΡΣ-ҁҊ-Ֆՠ-ֈא-ת]'
		return str
	elseif (prevQuote > 0 && nextQuote >= prevQuote) # 直前が引用符で、その個数が直後の個数以上
		return ForwardCursor()
	elseif prevQuote > 4                    # 直前引用符 4 つより多い
		if nextQuote > 0                        # 次も引用符ならカーソル移動
			return ForwardCursor()
		endif
		return InPairNextPrev(pline, nline)
	elseif prevQuote >= 2                   # 直前複数引用符
		if IsOddQuote(pline) && !IsOddQuote(nline)
			return str
		endif
		# 直後の個数が直前より多い場合は、これより上で済んでいるので、直後を直前と同じ個数にして間にカーソル移動
		var q: string
		prevQuote -= nextQuote
		for i in range(prevQuote)
			q ..= str
		endfor
		for i in range(prevQuote)
			q ..= BackCursor()
		endfor
		return q
	endif
	return InPairNextPrev(pline, nline)
enddef

def CR(): string # 改行の入力
	var pline: string
	var nline: string

	if mode(1) =~# '^R' || getcmdwintype() !=# ''
		return "\<CR>"
	endif
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket)
		if match(nline, '^' .. escape(v.pair, '.$*~\[]')) != -1 && match(pline, escape(k, '.$*~\[]') .. '$') != -1
			# return "\<CR>\<Esc>\<S-o>"
			# ↓だと↑より /**/ 中の改行で行頭に * が付きにくい
			return "\<CR>\<Esc>ko"
			# undo の塊を分割させない様に試みた方法
			# return "X" .. BackCursor() .. "\<CR>" .. ForwardCursor() .. "\<CR>\<C-O>:call setpos('.', [0, line('.') - 1, col('.') + 10, 0])\<CR>\<BS>"
			# ↓<Up>, k で undo の塊が途切れる
			# return "X" .. BackCursor() .. "\<CR>" .. ForwardCursor() .. "\<CR>\<C-O>k\<Del>"
			# return "X" .. BackCursor() .. "\<CR>" .. ForwardCursor() .. "\<CR>\<C-R>=\"\<UP>\"\<CR>\<Del>"
			# ↓undojoin を試みたがだめだった
			# undojoin | execute 'call feedkeys("X" .. BackCursor() .. "\<CR>" .. ForwardCursor() .. "\<CR>", "n")'
			# undojoin | execute 'call feedkeys("\<C-O>k\<Del>", "n")'
			# 分ける位置を変えてもだめ
			# undojoin | execute 'call feedkeys("X" .. BackCursor() .. "\<CR>" .. ForwardCursor() .. "\<CR>\<C-O>k", "n")'
			# undojoin | execute 'call feedkeys("\<Del>", "n")'
			# setpos() は効かない
			# undojoin | execute 'call feedkeys("X" .. BackCursor() .. "\<CR>" .. ForwardCursor() .. "\<CR>", "n")'
			# setpos('.', [0, line('.') - 1, col('.') + 10, 0])
			# undojoin | execute 'call feedkeys("\<BS>", "n")'
			# return ""
		endif
	endfor
	return "\<CR>"
enddef

def Space(): string # スペースキーの入力
	var pline: string
	var nline: string

	if mode(1) =~# '^R'
		return "\<Space>"
	endif
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket)
		if get(v, 'space', 0)
			if match(pline, escape(k, '.$*~\[]') .. '$') != -1 && # カーソル前が開く括弧
				match(nline, '^' .. escape(v.pair, '.$*~\[]')) != -1 # カーソル位置が閉じ括弧
				return "\<Space>\<Space>" .. BackCursor()
			endif
		endif
	endfor
	# for [q, v] in items(g:pairquote) # 引用符の場合、スペースのペア入力が便利かどうか不明
	# 	if match(pline, escape(q, '.$*~\[]') .. '$') != -1 && # カーソル前が引用符
	# 		match(nline, '^' .. escape(q, '.$*~\[]')) != -1 # カーソル位置が同じ引用符
	# 		return "\<Space>\<Space>" .. BackCursor()
	# 	endif
	# endfor
	return "\<Space>"
enddef

def BS(): string # バックスペースの入力
	var pline: string
	var nline: string
	var checkStr: string

	def DeleteKey(b: string, c: string): string # <BS>と<Del>の組み合わせを生成
		var ret: string
		for i in range(strcharlen(b))
			ret ..= "\<BS>"
		endfor
		for i in range(strcharlen(c))
			ret ..= "\<Del>"
		endfor
		return ret
	enddef

	if mode(1) =~# '^R'
		return "\<BS>"
	endif
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket) # 括弧自身や内部空白をペアで削除
		for ft in get(v, 'type', [&filetype])
			if &filetype != ft
				continue
			endif
			if match(pline, escape(k, '.$*~\[]') .. '$') == -1 # カーソル前が開く括弧ではない
				continue
			endif
			checkStr = v.pair # ペアの括弧
			if match(nline, '^\\' .. escape(checkStr, '.$*~\[]')) != -1 # カーソル位置が \ + 閉じ括弧
				var escape: number = GetMode(strpart(pline, 0, strlen(pline) - strlen(k)), k, v)
				if escape == 2 # TeX の \[ \] や検索の正規表現 \( \) など
					return DeleteKey(k, '\' .. checkStr)
				elseif escape
					return DeleteKey(k, checkStr)
				else
					return "\<BS>"
				endif
			elseif match(nline, '^' .. escape(checkStr, '.$*~\[]')) != -1 # カーソル位置が閉じ括弧
				return DeleteKey(k, checkStr)
			elseif get(v, 'space', 0) # ペアの空白も削除対象
				&& match(pline, escape(k, '.$*~\[]') .. '\s\+$') != -1 # カーソル前が開く括弧とスペース
				&& match(nline, '^\s\+' .. escape(checkStr, '.$*~\[]')) != -1 # カーソル位置がスペースと閉じ括弧
				return "\<BS>\<Del>"
			endif
		endfor
	endfor
	for [q, v] in items(g:pairquote) # 引用符自身や内部空白をペアで削除
		checkStr = escape(q, '.$*~\[]')
		for ft in get(v, 'type', [&filetype])
			if &filetype != ft
				continue
			endif
			if (match(pline, checkStr .. '$') != -1 && match(nline, '^' .. checkStr) != -1) # カーソル前後が同じ引用符
				|| (match(pline, checkStr .. '\s\+$') != -1 && match(nline, '^\s\+' .. checkStr) != -1) # カーソル前後が空白と同じ引用符
				return "\<BS>\<Del>"
			endif
		endfor
	endfor
	return "\<BS>"
enddef
