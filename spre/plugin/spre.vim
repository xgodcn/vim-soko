
command! -bar -range=% SPHtml call s:SPHtml(<line1>, <line2>)
command! -bar -range=% -nargs=? SPToHtml call s:SPToHtml(<line1>, <line2>, <f-args>)

function! s:SPHtml(line1, line2)
  let lines = getline(a:line1, a:line2)
  new
  call setline(1, lines)
  setl ft=spre foldmethod=syntax
  " remove comment
  folddoopen if getline('.') =~ '^[#!]\{2}' | delete _ | endif
  " convert spre text
  folddoclosed call s:DoConvert()
endfunction

function! s:SPToHtml(line1, line2, ...)
  let colorscheme = get(a:000, 0, "")
  let attr = {}
  let attr["filetype"] = &ft
  let attr["tag"] = "pre"
  if colorscheme != ""
    let attr["colorscheme"] = colorscheme
  endif
  let lines = s:ToHtml(getline(a:line1, a:line2), attr)
  new
  call setline(1, lines)
endfunction

function! s:DoConvert()
  " foldclosed('.') may be different with line('.'), and line('.') is correct.
  if getline('.') =~ '^.macro\>'
    let expr = join(getline(line('.') + 1, foldclosedend('.') - 1), "\n")
    call append(line('.') - 1, s:ExecMacro(expr))
  else
    call append(line('.') - 1, s:ToTag(line('.'), foldclosedend('.')))
  endif
  silent execute printf("%d,%ddelete _", line('.'), foldclosedend('.'))
endfunction

function! s:ExecMacro(expr)
  " execute "augroup Group\nau!\naugroup END\n" will fail.
  " use temporary function to avoid such a problem.
  execute "function! s:__tmpfunc()\n" . a:expr . "\nreturn []\nendfunction"
  return s:__tmpfunc()
endfunction

function! s:ToTag(start, end)
  let lines = getline(a:start + 1, a:end - 1)
  let [_0, punct, name, ft, attr_str; _] = matchlist(getline(a:start), '\v^(.)(\w+)%(\s+(\w+)>)?%(\s+(.+))?')
  if attr_str == ""
    let attr = {}
  else
    let attr = eval(attr_str)
  endif
  let attr["filetype"] = ft
  let attr["tag"] = get(attr, "tag", "pre")
  let attr["class"] = get(attr, "class", ft)
  let attr["point"] = get(attr, "point", [])
  " BOGUS: protect global option
  if has_key(attr, "option")
    let save = {}
    let save["&listchars"] = &listchars
  endif
  let lines = s:ToHtml(lines, attr)
  if has_key(attr, "option")
    for [name, value] in items(save)
      if eval(name) != value
        execute printf("let %s = value", name)
      endif
    endfor
  endif
  return lines
endfunction

function! s:ToHtml(lines, attr)
  let save_colors_name = get(g:, "colors_name", "")
  if has_key(a:attr, "colorscheme")
    execute "colorscheme " . a:attr["colorscheme"]
  endif

  let style = s:syn_to_style(hlID("Normal"))

  new         " open tmp buffer
  call setline(1, a:lines)
  let &ft = a:attr["filetype"]

  if has_key(a:attr, "option")
    execute "setl " . a:attr["option"]
  endif

  if has_key(a:attr, "macro")
    call a:attr.macro()
  endif

  let lines = s:tohtml_internal(1, line('$'), a:attr)

  bwipeout!   " close tmp buffer

  if has_key(a:attr, "colorscheme") && save_colors_name != ""
    execute "colorscheme " . save_colors_name
  endif

  let class = (get(a:attr, "class", "") == "") ? "" : printf(' class="%s"', a:attr["class"])
  let style = (!has_key(a:attr, "colorscheme") || style == "") ? "" :  printf(' style="%s"', style)
  let lines[0] = printf('<%s%s%s>', get(a:attr, "tag"), class, style) . lines[0]
  let lines[-1] = lines[-1] . printf('</%s>', get(a:attr, "tag"))
  return lines
endfunction

let s:whatterm = "gui"

" reinventing the wheel
function! s:tohtml_internal(start, end, attr)
  let lines = []
  for lnum in range(a:start, a:end)
    let line = ""
    for [str, style] in s:getsynline(lnum, a:attr)
      let str = s:escape_html(str)
      if style == ""
        let line .= str
      else
        let tag = printf('<span style="%s">%s</span>', style, str)
        let line .= tag
      endif
    endfor
    call add(lines, line)
  endfor
  return lines
endfunction

function! s:getsynline(lnum, attr)
  let lst = []
  let vcol = 1
  let col = 1
  for c in split(getline(a:lnum), '\zs')
    if c == "\t" && &list
      if &listchars =~ 'tab:'
        let _ = matchlist(&listchars, 'tab:\(.\)\(.\)')
        let str = _[1] . repeat(_[2], s:tabwidth(vcol) - 1)
      else
        let str = "^I"
      endif
      for c in split(str, '\zs')
        let style = s:syn_to_style(hlID("SpecialKey"))
        let style = s:point_merge(a:lnum, vcol, style, a:attr["point"])
        call add(lst, [c, style])
        let vcol += 1
      endfor
      let col += 1
    else
      let style = s:syn_to_style(synIDtrans(synID(a:lnum, col, 1)))
      let style = s:point_merge(a:lnum, vcol, style, a:attr["point"])
      call add(lst, [c, style])
      let vcol += (c == "\t") ? s:tabwidth(vcol) : s:wcwidth(c)
      let col += len(c)
    endif
  endfor
  if &list && &listchars =~ 'trail:'
    let i = len(lst) - 1
    while i >= 0
      if lst[i][0] != " "
        break
      endif
      let style = s:syn_to_style(hlID("SpecialKey"))
      let c = matchstr(&listchars, 'trail:\zs.')
      let lst[i] = [c, style]
      let i -= 1
    endwhile
  endif
  if &list && &listchars =~ 'eol:'
    let style = s:syn_to_style(hlID("NonText"))
    let c = matchstr(&listchars, 'eol:\zs.')
    call add(lst, [c, style])
  endif
  for p in a:attr["point"]
    if a:lnum == p[0] && vcol <= p[1]
      if !(vcol == p[0] && &list && &listchars =~ 'eol:')
        for i in range(p[1] - vcol + 1)
          call add(lst, [" ", ""])
        endfor
      endif
      let lst[-1][1] = s:point_merge_style(lst[-1][1], p[2], p[3])
    endif
  endfor
  if &number
    let w = max([&numberwidth, len(line('$'))])
    let str = printf('%' . w . 'd ', a:lnum)
    let style = s:syn_to_style(hlID("LineNr"))
    call insert(lst, [str, style])
  endif
  " group with same attribute
  if len(lst) >= 2
    let i = 1
    while i < len(lst)
      if lst[i - 1][1] == lst[i][1]
        let lst[i - 1][0] .= lst[i][0]
        call remove(lst, i)
      else
        let i += 1
      endif
    endwhile
  endif
  return lst
endfunction

function! s:tabwidth(vcol)
  return &ts - ((a:vcol - 1) % &ts)
endfunction

function! s:wcwidth(c)
  return (a:c =~ '^.\%2v') ? 1 : 2
endfunction

" from 2html.vim
function! s:syn_to_style(id)
  let a = ""
  if synIDattr(a:id, "inverse")
    " For inverse, we always must set both colors (and exchange them)
    let x = synIDattr(a:id, "bg#", s:whatterm)
    let a = a . "color: " . ( x != "" ? x : s:bgc ) . "; "
    let x = synIDattr(a:id, "fg#", s:whatterm)
    let a = a . "background-color: " . ( x != "" ? x : s:fgc ) . "; "
  else
    let x = synIDattr(a:id, "fg#", s:whatterm)
    if x != "" | let a = a . "color: " . x . "; " | endif
    let x = synIDattr(a:id, "bg#", s:whatterm)
    if x != "" | let a = a . "background-color: " . x . "; " | endif
  endif
  if synIDattr(a:id, "bold") | let a = a . "font-weight: bold; " | endif
  if synIDattr(a:id, "italic") | let a = a . "font-style: italic; " | endif
  if synIDattr(a:id, "underline") | let a = a . "text-decoration: underline; " | endif
  return a
endfunction

function! s:point_merge(lnum, vcol, style, points)
  for p in a:points
    if a:lnum == p[0] && a:vcol == p[1]
      return s:point_merge_style(a:style, p[2], p[3])
    endif
  endfor
  return a:style
endfunction

function! s:point_merge_style(style, width, hlname)
  if a:width == 0
    return s:syn_to_style(hlID(a:hlname))
  elseif a:hlname == "Cursor" || a:hlname == "CursorIM"
    let color = matchstr(s:syn_to_style(hlID(a:hlname)), 'background-color:\s*\zs\(\S\+\)\ze;')
    if color != ""
      return a:style . printf("border-left: %dpx solid %s;", a:width, color)
    endif
  else
    let color = matchstr(s:syn_to_style(hlID(a:hlname)), 'color:\s*\zs\(\S\+\)\ze;')
    if color != ""
      return a:style . printf("border-left: %dpx solid %s;", a:width, color)
    endif
  endif
  return a:style
endfunction

function! s:escape_html(str)
  let str = a:str
  let str = substitute(str, '&', '\&amp;', 'g')
  let str = substitute(str, '<', '\&lt;', 'g')
  let str = substitute(str, '>', '\&gt;', 'g')
  let str = substitute(str, '"', '\&quot;', 'g')
  let str = substitute(str, ' ', '\&nbsp;', 'g')
  return str
endfunction

