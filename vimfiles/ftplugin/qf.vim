nnoremap <buffer> <silent> d  :<C-U>set operatorfunc=<SID>qf_dd<CR>g@
nnoremap <buffer> <silent> dd :<C-U>set operatorfunc=<SID>qf_dd<CR>g@g@
vnoremap <buffer> <silent> d  :<C-U>set operatorfunc=<SID>qf_dd<CR>gvg@
nmap     <buffer> <silent> D  dd
vmap     <buffer> <silent> D  d

if exists('s:loaded')
  finish
endif
let s:loaded = 1

function! s:qf_dd(type)
  let firstline = line("'[")
  let lastline = line("']")
  let nlines = lastline - firstline + 1
  let loc = getloclist(0)
  let qf = getqflist()
  let view = winsaveview()
  if !empty(loc)
    ll
    lopen
    let currentline = line('.')
    unlet loc[firstline - 1 : lastline - 1]
    call setloclist(0, loc, 'r')
    if !empty(loc)
      if currentline <= firstline
        execute 'll' currentline
      elseif firstline < currentline && currentline <= lastline
        execute 'll' firstline
      else "if lastline < currentline
        execute 'll' (currentline - nlines)
      endif
    endif
    lopen
  elseif !empty(qf)
    cc
    copen
    let currentline = line('.')
    unlet qf[firstline - 1 : lastline - 1]
    call setqflist(qf, 'r')
    if !empty(qf)
      if currentline <= firstline
        execute 'cc' currentline
      elseif firstline < currentline && currentline <= lastline
        execute 'cc' firstline
      else "if lastline < currentline
        execute 'cc' (currentline - nlines)
      endif
    endif
    copen
  endif
  call winrestview(view)
endfunction
