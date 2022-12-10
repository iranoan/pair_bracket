vim9script
scriptencoding utf-8

export def Init(): void
	def SetBracket(s1: string, s2: dict<any>): void
		var k = substitute(s1, '|', '<Bar>', 'g')
		var v = substitute(substitute(s1, '''', '''''', 'g'), '|', '\\|', 'g')

		execute 'inoremap <expr>' .. k .. ' <SID>InputBra(''' .. v .. ''')'
		execute 'cnoremap <expr>' .. k .. ' <SID>InputBra(''' .. v .. ''')'
		k = substitute(s2.pair, '|', '<Bar>', 'g')
		v = substitute(substitute(s2.pair, '''', '''''', 'g'), '|', '\\|', 'g')
		execute 'inoremap <expr>' .. k .. ' <SID>InputCket(''' .. v .. ''')'
		execute 'cnoremap <expr>' .. k .. ' <SID>InputCket(''' .. v .. ''')'
	enddef

	def SetQuote(s: string): void
		var k = substitute(s, '|', '<Bar>', 'g')
		var q = substitute(substitute(s, '''', '''''', 'g'), '|', '\\|', 'g')

		execute 'inoremap <expr>' .. k .. ' <SID>Quote(''' .. q .. ''')'
		execute 'cnoremap <expr>' .. k .. ' <SID>Quote(''' .. q .. ''')'
	enddef

	g:pairbracket = get(g:, 'pairbracket', {
		'{': {'pair': '}', 'space': 1},
		'[': {'pair': ']', 'space': 1},
		'(': {'pair': ')', 'space': 1}
		})
	g:pairquote = get(g:, 'pairquote', {
		'''': {},
		'"': {},
		'`': {}
		})
	for [k, v] in items(g:pairbracket)
		SetBracket(k, v)
	endfor
	for [k, v] in items(g:pairquote)
		SetQuote(k)
	endfor
	inoremap <expr><BS>    <SID>BS()
	cnoremap <expr><BS>    <SID>BS()
	inoremap <expr><CR>    <SID>CR()
	inoremap <expr><Space> <SID>Space()
	cnoremap <expr><Space> <SID>Space()
enddef

def SeparateLine(): list<string> # カーソルより前/後のカーソル行の文字列
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

def MatchBraCket(line1: string, line2: string, bra: string, cket: string): list<number>
	# 未対応の開き括弧の数
	var cket_pos: number
	var bra_pos: number
	var pline = substitute(substitute(line1, '\\\\', '', 'g'), '\\' .. escape(bra, '.$*~\'), '', 'g')
	var nline = substitute(substitute(line2, '\\\\', '', 'g'), '\\' .. escape(cket, '.$*~\'), '', 'g')

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

def InputBra(str: string): string # 括弧などをペアで入力
	var pline: string
	var nline: string
	var prevMatch: number
	var nextMatch: number
	var pairStr: string
	var move: string
	var rl = (mode(1) !~# '^c' && &rightleft) ? "\<Right>" : "\<Left>"

	if mode(1) =~# '^R' || index(get(g:pairbracket[str], 'type', [&filetype]), &filetype) == -1
		return str
	endif
	[pline, nline] = SeparateLine()
	pairStr = g:pairbracket[str].pair
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, str, pairStr)
	if prevMatch >= nextMatch
		for i in range(strcharlen(pairStr))
			move ..= rl
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

	if mode(1) =~# '^R'
		return str
	endif
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket)
		if str ==# v.pair
			pairStr = k
			break
		endif
	endfor
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, pairStr, str)
	if match(nline, '^' .. escape(str, '.$*~\')) !=# -1 && prevMatch <= nextMatch
		return (mode(1) !~# '^c' && &rightleft) ? "\<Left>" : "\<Right>"
	else
		return str
	endif
enddef

def Quote(str: string): string # クォーテーションの入力
	var rl = (mode(1) !~# '^c' && &rightleft) ? "\<Right>" : "\<Left>"
	var pline: string
	var nline: string
	var prevChar: string
	var nextQuote: number
	var prevQuote: number

	def InPair(): string
		var ret = str .. str

		for i in range(strcharlen(str))
			ret ..= rl
		endfor
		return ret
	enddef

	def InPairNextPrev(p: string, n: string): string # 直前/直後に限らずカーソルより前 (p)/後 (n) の引用記号個数に応じて、ペア入力か否かを変える
		var is_prev_odd: number # カーソルより前に有る引用符が奇数個か?
		var is_next_odd: number # カーソルより前に有る引用符が奇数個か?

		def IsOddQuote(l: string): number # 引用符の個数が奇数個か?
			return count(substitute(substitute(l, '\\\\', '', 'g'), '\\' .. escape(str, '.$*~\'), '', 'g'), str) % 2
		enddef

		is_prev_odd = IsOddQuote(p) # カーソルより前に有る引用符が奇数個か?
		is_next_odd = IsOddQuote(n) # カーソルより前に有る引用符が奇数個か?
		if is_prev_odd == is_next_odd
			return InPair()
		elseif is_prev_odd
			return str
		else
			return InPair()
		endif
	enddef

	if mode(1) =~# '^R' || index(get(g:pairquote[str], 'type', [&filetype]), &filetype) == -1
		return str
	endif
	[pline, nline] = SeparateLine()
	prevChar = matchstr(pline, '.$')
	nextQuote = strlen(matchstr(nline, '^' .. escape(str, '.$*~\') .. '\+'))
	prevQuote = strlen(matchstr(pline, escape(str, '.$*~\') .. '\+$'))
	if strlen(matchstr(pline, '\\\+$')) % 2 # 直前が \ でエスケープされている
		|| prevChar =~# '\a'                  # 直前が欧文数字
		|| prevChar =~# '\d'
		|| prevChar =~# '[À-öø-ƿǄ-ʯͲͳͶͷͻ-ͽͲͳͶͷͻ-ͽΌΎ-ΡΣ-ҁҊ-Ֆՠ-ֈא-ת]'
		return str
	elseif (prevQuote > 0 && nextQuote >= prevQuote) # 直前が引用符で、その個数が直後の個数以上
		return (mode(1) !~# '^c' && &rightleft) ? "\<Left>" : "\<Right>"
	elseif prevQuote > 4                    # 直前引用符 3 つより多い
		if nextQuote > 0                        # 次も引用符ならカーソル移動
			return (mode(1) !~# '^c' && &rightleft) ? "\<Left>" : "\<Right>"
		endif
		return InPairNextPrev(pline, nline)
	elseif prevQuote >= 2                   # 直前複数引用符
		# 直後の個数が直前より多い場合は、これより上で済んでいるので、直後を直前と同じ個数にして間にカーソル移動
		var q: string
		prevQuote -= nextQuote
		for i in range(prevQuote)
			q ..= str
		endfor
		for i in range(prevQuote)
			q ..= rl
		endfor
		return q
	endif
	return InPairNextPrev(pline, nline)
enddef

def CR(): string # 改行の入力
	var pline: string
	var nline: string

	if mode(1) =~# '^R'
		return str
	endif
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket)
		if match(nline, '^' .. escape(v.pair, '.$*~\')) != -1 && match(pline, escape(k, '.$*~\') .. '$') != -1
			# return "\<CR>\<Esc>\<S-o>"
			# ↓だと↑より /**/ 中の改行で行頭に * が付きにくい
			return "\<CR>\<Esc>ko"
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
			if match(pline, escape(k, '.$*~\') .. '$') != -1 && # カーソル前が開く括弧
				match(nline, '^' .. escape(v.pair, '.$*~\')) != -1 # カーソル位置が閉じ括弧
				return "\<Space>\<Space>" .. ( (mode(1) !~# '^c' && &rightleft) ? "\<Right>" : "\<Left>" )
			endif
		endif
	endfor
	# for [q, v] in items(g:pairquote) # 引用符の場合、スペースのペア入力が便利かどうか不明
	# 	if match(pline, escape(q, '.$*~\') .. '$') != -1 && # カーソル前が引用符
	# 		match(nline, '^' .. escape(q, '.$*~\')) != -1 # カーソル位置が同じ引用符
	# 		return "\<Space>\<Space>" .. ( (mode(1) !~# '^c' && &rightleft) ? "\<Right>" : "\<Left>" )
	# 	endif
	# endfor
	return "\<Space>"
enddef

def BS(): string # バックスペースの入力
	var pline: string
	var nline: string
	var checkStr: string

	if mode(1) =~# '^R'
		return "\<BS>"
	endif
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket) # 括弧自身や内部空白をペアで削除
		for ft in get(v, 'type', [&filetype])
			if &filetype != ft
				continue
			endif
			# ペアの括弧
			checkStr = v.pair
			if match(pline, escape(k, '.$*~\') .. '$') != -1 && # カーソル前が開く括弧
				match(nline, '^' .. escape(checkStr, '.$*~\')) != -1 # カーソル位置が閉じ括弧
				var ret: string
				for i in range(strcharlen(k))
					ret ..= "\<BS>"
				endfor
				for i in range(strcharlen(checkStr))
					ret ..= "\<Del>"
				endfor
				return ret
			endif
			if get(v, 'space', 0) # ペアの空白
				if match(pline, escape(k, '.$*~\') .. '\s\+$') != -1 && # カーソル前が開く括弧とスペース
					match(nline, '^\s\+' .. escape(checkStr, '.$*~\')) != -1 # カーソル位置がスペースと閉じ括弧
					return "\<BS>\<Del>"
				endif
			endif
		endfor
	endfor
	for [q, v] in items(g:pairquote) # 引用符自身や内部空白をペアで削除
		checkStr = escape(q, '.$*~\')
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
