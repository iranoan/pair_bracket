vim9script
# Author:  Iranoan <iranoan+vim@gmail.com>
# License: GPL Ver.3.

scriptencoding utf-8

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

def DeleteEscaped(l: string, s: string, dic: dict<any>): string
	var escape_c: string

	if getcmdtype() ==# ':' || getcmdwintype() ==# ':'
		escape_c = get(dic, 'escape_char', {'vim': '\'})['vim']
	else
		escape_c = get(dic, 'escape_char', {})->get(&filetype, '\')
	endif
	if escape_c ==# '\'
		return substitute(substitute(l, '\\\\', '', 'g'), '\\' .. escape(s, '.$*~\'), '', 'g')
	else
		return substitute(substitute(l, escape(escape_c .. escape_c, '.$*~\'), '', 'g'), escape(escape_c .. s, '.$*~\'), '', 'g')
	endif
enddef

def GetMode(s: string, d: dict<any>): number # 検索モード、通常のコマンドライン、入力モードのペア括弧の入力方法を返す
	var escape: number    # ペア括弧の入力方法

	def Search(): number
		if match(s, '\\v') == -1
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

	if strlen(matchstr(s, '\\\+$')) % 2 # 直前が \ でエスケープされている
		escape = 1
	endif
	if getcmdtype() =~# '[/?]' || getcmdwintype() =~# '/?:'
		return Search()
	elseif escape
		return get(d, 'escape', )->get(&filetype, 0)
	else # 検索モードでもなくエスケープもされていない
		return 1 # 標準のペア入力
	endif
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
	var rl = (mode(1) !~# '^c' && &rightleft) ? "\<Right>" : "\<Left>"

	if mode(1) =~# '^R'
		|| (!get(pair_dic, 'cmap', 1) && (getcmdtype() ==# ':' || getcmdwintype() ==# ':'))
		return str
	endif
	[pline, nline] = SeparateLine()
	escape = GetMode(pline, pair_dic)
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
	for [k, v] in items(g:pairbracket)
		if str ==# v.pair
			if !get(g:pairbracket[k], 'cmap', 1) && getcmdwintype() !=# ''
				return str
			endif
			pairStr = k
			break
		endif
	endfor
	[pline, nline] = SeparateLine()
	if strlen(matchstr(pline, '\\\+$')) % 2 # 直前が \ でエスケープされている
		return str
	endif
	[prevMatch, nextMatch] = MatchBraCket(pline, nline, pairStr, str, pair_dic)
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
	var pair_dic: dict<any> = g:pairquote[str]

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
			return count(DeleteEscaped(l, str, pair_dic), str) % 2
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

	if mode(1) =~# '^R'
		|| (!get(pair_dic, 'cmap', 1) && (getcmdtype() ==# ':' || getcmdwintype() ==# ':'))
		|| (!get(pair_dic, 'search', 0) && getcmdtype() =~# '[/?]' || getcmdwintype() =~# '/?:')
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

	if mode(1) =~# '^R' || getcmdwintype() !=# ''
		return "\<CR>"
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
			if match(pline, escape(k, '.$*~\') .. '$') == -1 # カーソル前が開く括弧ではない
				continue
			endif
			checkStr = v.pair # ペアの括弧
			if match(nline, '^\\' .. escape(checkStr, '.$*~\')) != -1 # カーソル位置が \ + 閉じ括弧
				var escape: number = GetMode(pline[ : - strlen(k) - 1], v)
				if escape == 2 # TeX の \[ \] や検索の正規表現 \( \) など
					return DeleteKey(k, '\' .. checkStr)
				elseif escape
					return DeleteKey(k, checkStr)
				else
					return "\<BS>"
				endif
			elseif match(nline, '^' .. escape(checkStr, '.$*~\')) != -1 # カーソル位置が閉じ括弧
				return DeleteKey(k, checkStr)
			elseif get(v, 'space', 0) # ペアの空白も削除対象
				&& match(pline, escape(k, '.$*~\') .. '\s\+$') != -1 # カーソル前が開く括弧とスペース
				&& match(nline, '^\s\+' .. escape(checkStr, '.$*~\')) != -1 # カーソル位置がスペースと閉じ括弧
				return "\<BS>\<Del>"
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
