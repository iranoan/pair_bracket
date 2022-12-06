vim9script
scriptencoding utf-8

export def Init(): void
	def SetBracket(s1: string, s2: dict<any>): void
		var k = substitute(s1, '|', '<Bar>', 'g')
		var v = substitute(substitute(s1, '''', '''''', 'g'), '|', '\\|', 'g')
		execute 'inoremap <expr>' .. k .. ' <SID>InputBra(''' .. v .. ''')'
		k = substitute(s2.pair, '|', '<Bar>', 'g')
		v = substitute(substitute(s2.pair, '''', '''''', 'g'), '|', '\\|', 'g')
		execute 'inoremap <expr>' .. k .. ' <SID>InputCket(''' .. v .. ''')'
	enddef

	def SetQuote(s: string): void
		var k = substitute(s, '|', '<Bar>', 'g')
		var q = substitute(substitute(s, '''', '''''', 'g'), '|', '\\|', 'g')
		execute 'inoremap <expr>' .. k .. ' <SID>Quote(''' .. q .. ''')'
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
	inoremap <expr><CR>    <SID>CR()
	inoremap <expr><Space> <SID>Space()
	inoremap <expr><BS>    <SID>BS()
enddef

def SeparateLine(): list<string> # カーソルより前/後のカーソル行の文字列
	var column = col('.')
	var nline = getline('.')
	return [strpart(nline, 0, column - 1), strpart(nline, column - 1)]
enddef

def MatchBraCket(line1: string, line2: string, bra: string, cket: string): list<number>
	# 未対応の開き括弧の数
	var cket_pos: number
	var bra_pos: number
	var pline = substitute(substitute(line1, '\\\\', '', 'g'), '\\' .. bra, '', 'g')
	var nline = substitute(substitute(line2, '\\\\', '', 'g'), '\\' .. cket, '', 'g')
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
	if index(get(g:pairbracket[str], 'type', [&filetype]), &filetype) == -1
		return str
	endif
	var pline: string
	var nline: string
	[pline, nline] = SeparateLine()
	var pairStr = g:pairbracket[str].pair
	var prevMatch: number
	var nextMatch: number
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, str, pairStr)
	if prevMatch >= nextMatch
		var move: string
		var rl = &rightleft ? "\<Right>" : "\<Left>"
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
	[pline, nline] = SeparateLine()
	var pairStr: string
	for [k, v] in items(g:pairbracket)
		pairStr = g:pairbracket[k].pair
		if str ==# pairStr
			pairStr = k
			break
		endif
	endfor
	var prevMatch: number
	var nextMatch: number
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, pairStr, str)
	if match(nline, '^' .. escape(str, '.$*~\')) !=# -1 && prevMatch <= nextMatch
		return &rightleft ? "\<Left>" : "\<Right>"
	else
		return str
	endif
enddef

def Quote(str: string): string # クォーテーションの入力
	var rl = &rightleft ? "\<Right>" : "\<Left>"
	def Inpair(s: string): string
		var ret = s .. s
		for i in range(strcharlen(s))
			ret ..= rl
		endfor
		return ret
	enddef
	if index(get(g:pairquote[str], 'type', [&filetype]), &filetype) == -1
		return str
	endif
	var pline: string
	var nline: string
	[pline, nline] = SeparateLine()
	var nextChar = matchstr(nline, '.')
	var prevChar = matchstr(pline, '.$')
	var nextQuote = strlen(matchstr(nline, '^' .. escape(str, '.$*~\') .. '\+'))
	var prevQuote = strlen(matchstr(pline, escape(str, '.$*~\') .. '\+$'))
	if strlen(matchstr(pline, '\\\+$')) % 2  # 直前が \ でエスケープされている
		return str
	elseif prevQuote >= 2 # 直前が連続する引用符
		if nextQuote == prevQuote # 直前/直後が同一個数→カーソル移動
			return &rightleft ? "\<Left>" : "\<Right>"
		endif
		# 直前/直後の個数が異なるので、直後を直前と同じ個数にして間にカーソル移動
		var q: string
		prevQuote -= nextQuote
		for i in range(prevQuote)
			q ..= str
		endfor
		for i in range(prevQuote)
			q ..= rl
		endfor
		return q
	elseif nextChar ==# str
		return &rightleft ? "\<Left>" : "\<Right>"
	elseif prevChar =~# '\a' || (prevChar =~# '\d') || prevChar =~# '[À-öø-ƿǄ-ʯͲͳͶͷͻ-ͽͲͳͶͷͻ-ͽΌΎ-ΡΣ-ҁҊ-Ֆՠ-ֈא-ת]'
		return str
	endif
	return Inpair(str)
enddef

def CR(): string # 改行の入力
	var pline: string
	var nline: string
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
	[pline, nline] = SeparateLine()
	for [k, v] in items(g:pairbracket)
		if get(v, 'space', 0)
			if match(pline, escape(k, '.$*~\') .. '$') != -1 && # カーソル前が開く括弧
				match(nline, '^' .. escape(v.pair, '.$*~\')) != -1 # カーソル位置が閉じ括弧
				return "\<Space>\<Space>" .. ( &rightleft ? "\<Right>" : "\<Left>" )
			endif
		endif
	endfor
	return "\<Space>"
enddef

def BS(): string # バックスペースの入力
	var pline: string
	var nline: string
	[pline, nline] = SeparateLine()
	var checkStr: string
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
	for [q, v] in items(g:pairquote) # 引用符削除
		checkStr = escape(q, '.$*~\')
		for ft in get(v, 'type', [&filetype])
			if &filetype != ft
				continue
			endif
			if match(pline, checkStr .. '$') != -1 && # カーソル前が引用符
				match(nline, '^' .. checkStr) != -1 # カーソル位置が引用符
				return "\<BS>\<Del>"
			endif
		endfor
	endfor
	return "\<BS>"
enddef
