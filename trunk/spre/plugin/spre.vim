
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
  let lines = s:ToHtml(getline(a:line1, a:line2), "pre", &ft, colorscheme)
  new
  call setline(1, lines)
endfunction

function! s:DoConvert()
  call append(line('.') - 1, s:ToTag(foldclosed('.'), foldclosedend('.')))
  silent execute printf("%d,%ddelete _", foldclosed('.'), foldclosedend('.'))
endfunction

function! s:ToTag(start, end)
  let lines = getline(a:start + 1, a:end - 1)
  let [_0, punct, name, ft, color, opt; _] = matchlist(getline(a:start), '\v^(.)(\w+)%(\s+(\w+)\_s@=)?%(\s+(\w+)\_s@=)?%(\s+set:(.*))?')
  return s:ToHtml(lines, name, ft, color, opt)
endfunction

function! s:ToHtml(lines, tag, ft, color, opt)
  let save_colors_name = get(g:, "colors_name", "")
  if a:color != ""
    execute "colorscheme " . a:color
  endif

  new         " open tmp buffer
  call setline(1, a:lines)
  let &ft = a:ft

  if a:opt =~ '\S'
    execute "setl " . a:opt
  endif

  " let lines = s:tohtml_2html(1, line('$'))
  let lines = s:tohtml_internal(1, line('$'))

  bwipeout!   " close tmp buffer

  if a:color != "" && save_colors_name != ""
    execute "colorscheme " . save_colors_name
  endif

  let class = (a:ft == "") ? "" : printf(' class="%s"', a:ft)
  let style = (a:color == "") ? "" :  printf(' style="color: %s; background-color: %s;"',fg, bg)
  let lines[0] = printf('<%s%s%s>', a:tag, class, style) . lines[0]
  let lines[-1] = lines[-1] . printf('</%s>', a:tag)
  return lines
endfunction

function! s:tohtml_2html(start, end)
  if exists("g:html_use_css")
    let html_use_css_save = g:html_use_css
    unlet g:html_use_css
  endif
  if exists("g:html_no_pre")
    let html_no_pre_save = g:html_no_pre
    unlet g:html_no_pre
  endif
  execute printf("%d,%dTOhtml", a:start, a:end)
  if exists("html_use_css_save")
    let g:html_use_css = html_use_css_save
  endif
  if exists("html_no_pre_save")
    let g:html_no_pre = html_no_pre_save
  endif
  let [_0, bg, fg; _] = matchlist(getline(search('<body')), 'bgcolor="\([^"]*\)" text="\([^"]*\)"')
  silent 1,/<body/delete _
  silent /<\/body>/,$delete _
  silent %s@<font color="\([^"]*\)">@<span style="color: \1">@ge
  silent %s@</font>@</span>@ge
  silent %s@<br\s*/\?>@@ge
  silent %s@&nbsp;@ @ge
  let lines = getline(1, '$')
  bwipeout!   " close TOhtml buffer
  return lines
endfunction

let s:whatterm = "gui"

" reinventing the wheel
function! s:tohtml_internal(start, end)
  let lines = []
  for lnum in range(a:start, a:end)
    let line = ""
    for [str, style] in s:getsynline(lnum)
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

function! s:getsynline(lnum)
  let lst = []
  let vcol = 1
  let col = 1
  for c in split(getline(a:lnum), '\zs')
    if c == "\t" && &list
      if &listchars =~ 'tab:'
        let _ = matchlist(&listchars, 'tab:\(.\)\(.\)')
        let c = _[1] . repeat(_[2], s:tabwidth(vcol) - 1)
      else
        let c = "^I"
      endif
      let style = s:syn_to_style(hlID("SpecialKey"))
      let vcol += len(c)
    else
      let style = s:syn_to_style(synIDtrans(synID(a:lnum, col, 1)))
      let vcol += s:wcwidth(c)
    endif
    let col += len(c)
    call add(lst, [c, style])
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

function! s:escape_html(str)
  let str = a:str
  let str = substitute(str, '&', '\&amp;', 'g')
  let str = substitute(str, '<', '\&lt;', 'g')
  let str = substitute(str, '>', '\&gt;', 'g')
  let str = substitute(str, '"', '\&quot;', 'g')
  let str = substitute(str, ' ', '\&nbsp;', 'g')
  return str
endfunction

