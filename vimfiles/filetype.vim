if exists("did_load_filetypes")
  finish
endif
augroup filetypedetect
  autocmd BufRead,BufNewFile *.as           setf javascript
  autocmd BufRead,BufNewFile SConstruct     setf python
augroup END
