nnoremap <buffer> <silent> <script> d :<C-U>set operatorfunc=<SID>qf_d<CR><SID>[count]g@
vnoremap <buffer> <silent> <script> d :<C-U>set operatorfunc=<SID>qf_d<CR>gv<SID>[count]g@
nmap     <buffer> <silent> D dd
vmap     <buffer> <silent> D d
onoremap <buffer> <expr> d <SID>op_double('<SID>qf_d')
nnoremap <buffer> <expr> <SID>[count] v:count == 0 ? "" : v:count
vnoremap <buffer> <expr> <SID>[count] v:prevcount == 0 ? "" : v:prevcount

if exists('s:loaded')
  finish
endif
let s:loaded = 1

function! s:op_double(funcname)
  let funcname = a:funcname
  if stridx(funcname, "\<SNR>") == 0
    let funcname = "<SNR>" . funcname[3:]
  endif
  if v:operator == "g@" && &operatorfunc != funcname
    return "\<Esc>"
  endif
  return "g@"
endfunction

function! s:qf_d(type)
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
