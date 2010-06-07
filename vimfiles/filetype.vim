if exists("did_load_filetypes")
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

augroup filetypedetect
  autocmd BufRead,BufNewFile *.as           setf javascript
  autocmd BufRead,BufNewFile SConstruct     setf python
  autocmd BufRead,BufNewFile,StdinReadPost * call s:detect()
augroup END

function s:detect()
  if getline(1) =~ '^# HG changeset patch'
    setf diff
  endif
endfunction

let &cpo = s:cpo_save
unlet s:cpo_save
