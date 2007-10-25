
" Do not check b:current_syntax, so that spre can be combined with other
" syntax (e.g. set ft=html.spre)
" if exists("b:current_syntax")
"   finish
" endif

let s:cpo_save = &cpo
set cpo&vim

function! s:Setup()
  if exists("b:current_syntax")
    let current_syntax_save = b:current_syntax
  endif

  hi link MacroTag Macro
  hi link MacroComment Comment

  " comment
  syntax match MacroComment /^[#!]\{2}.*$/

  let ft_list = {}
  let ft_list["vim"] = 1

  " pre
  let pos = getpos('.')
  silent g/\v^[#!]%(pre)\s+\w+>/let ft_list[matchstr(getline('.'), '\v^[#!]%(pre)\s+\zs\w+>')] = 1
  call setpos('.', pos)
  syntax region MacroPre matchgroup=MacroTag start=/\v^\z([#!])%(pre)>.*$/ end=/^\z1end\>/ keepend extend fold
  for ft in keys(ft_list)
    if ft == "spre"
      continue
    endif
    unlet! b:current_syntax
    silent! execute printf('syntax include @G%s syntax/%s.vim', ft, ft)
    execute printf('syntax region MacroPre matchgroup=MacroTag start=/\v^\z([#!])%(pre)\s+%s>.*$/ end=/^\z1end\>/ contains=@G%s keepend extend fold', ft, ft)
  endfor

  " macro
  syntax region MacroPre matchgroup=MacroTag start=/\v^\z([#!])%(macro)>.*$/ end=/^\z1end\>/ contains=@Gvim keepend extend fold

  syntax region MacroSpre matchgroup=MacroTag start=/\v^\z([#!])%(pre)\s+spre>.*$/ end=/^\z1end\>/ contains=MacroComment,MacroPre,MacroSpre keepend extend fold

  let b:current_syntax = "spre"

  if exists("current_syntax_save")
    let b:current_syntax = current_syntax_save
  endif
endfunction

call s:Setup()

let &cpo = s:cpo_save
unlet s:cpo_save

