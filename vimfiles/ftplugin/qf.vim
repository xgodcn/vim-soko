nnoremap <buffer> <silent> dd :<C-U>call <SID>qf_dd()<CR>

if exists('s:loaded')
  finish
endif
let s:loaded = 1

function! s:qf_dd()
  let loc = getloclist(0)
  let qf = getqflist()
  let del = line('.')
  let view = winsaveview()
  if !empty(loc)
    ll
    lopen
    let cur = line('.')
    unlet loc[del - 1]
    call setloclist(0, loc, 'r')
    if !empty(loc)
      if del < cur
        let cur -= 1
      endif
      execute 'll' cur
    endif
    lopen
  elseif !empty(qf)
    cc
    copen
    let cur = line('.')
    unlet qf[del - 1]
    call setqflist(qf, 'r')
    if !empty(qf)
      if del < cur
        let cur -= 1
      endif
      execute 'cc' cur
    endif
    copen
  endif
  call winrestview(view)
endfunction
