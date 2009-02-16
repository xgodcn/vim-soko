" Last Change: 2009-02-17
"
" :nmap mm <Plug>MarkerToggle
" :vmap m  <Plug>MarkerToggle
" :NoMarker

if exists("loaded_marker")
  finish
endif
let loaded_marker = 1

let s:save_cpo = &cpo
set cpo&vim

hi default Marker1 ctermfg=black ctermbg=cyan    guifg=black guibg=cyan
hi default Marker2 ctermfg=black ctermbg=green   guifg=black guibg=green
hi default Marker3 ctermfg=black ctermbg=magenta guifg=black guibg=magenta
hi default Marker4 ctermfg=black ctermbg=red     guifg=black guibg=red
hi default Marker5 ctermfg=black ctermbg=blue    guifg=black guibg=blue
hi default Marker6 ctermfg=black ctermbg=yellow  guifg=black guibg=yellow

nnoremap <silent> <Plug>MarkerToggle :<C-U>call <SID>MarkerToggleN()<CR>
vnoremap <silent> <Plug>MarkerToggle :<C-U>call <SID>MarkerToggleV()<CR>

if !exists(':NoMarker')
  command! -count NoMarker call s:ClearMarker(<count>)
endif

function! s:MarkerToggleN()
  let group = 'Marker' . v:count1
  let pat = '\V\<' . expand('<cword>') . '\>'
  call s:ToggleMarker(group, pat)
endfunction

function! s:MarkerToggleV()
  let group = 'Marker' . v:count1
  let pat = '\V' . s:EscapePattern(s:GetVisualSelection())
  call s:ToggleMarker(group, pat)
endfunction

function! s:ToggleMarker(group, pat)
  let matches = getmatches()
  for m in matches
    if m.pattern ==# a:pat
      call matchdelete(m.id)
      return
    endif
  endfor
  call matchadd(a:group, a:pat)
endfunction

function! s:ClearMarker(...)
  let cnt = get(a:000, 0, 0)
  if cnt
    let group = '^Marker' . cnt . '$'
  else
    let group = '^Marker.*$'
  endif
  for m in getmatches()
    if m.group =~ group
      call matchdelete(m.id)
    endif
  endfor
endfunction

function! s:GetVisualSelection()
  let reg_restore = ['z', getreg('z'), getregtype('z')]
  silent normal! gv"zy
  let z = @z
  call call('setreg', reg_restore)
  return z
endfunction

function! s:EscapePattern(str)
  return substitute(escape(a:str, '\'), '\n', '\\n', 'g')
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
