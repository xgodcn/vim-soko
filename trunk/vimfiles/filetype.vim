if exists("did_load_filetypes")
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

augroup filetypedetect
  autocmd BufRead,BufNewFile *.as           setf javascript
  autocmd BufRead,BufNewFile SConstruct     setf python
augroup END

let &cpo = s:cpo_save
unlet s:cpo_save
