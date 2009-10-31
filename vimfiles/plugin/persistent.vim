" Last Change: 2009-10-31

if exists("loaded_persistent")
  finish
endif
let loaded_persistent = 1

if !exists("g:persistent_savedir")
  if isdirectory(expand("~/.vim"))
    let g:persistent_savedir = "~/.vim/persistent"
  elseif isdirectory(expand("~/vimfiles"))
    let g:persistent_savedir = "~/vimfiles/persistent"
  else
    echoerr "Cannot find ~/.vim or ~/vimfiles directory"
    finish
  endif
endif

let g:persistent_savedir = fnamemodify(g:persistent_savedir, ':p:s?/$??')

if !exists("g:persistent_options")
  let g:persistent_options = ["&l:sw", "&l:sts", "&l:ts", "&l:et"]
endif

augroup PlugPersistent
  au!
  autocmd BufRead,BufNewFile * call s:Load(bufname("%"))
  autocmd BufLeave,BufUnload * call s:Save(expand("<afile>"))
augroup END

function! s:Load(bufname)
  let ft = (&ft != '' ? &ft : '_')
  let dir = s:GetPath(a:bufname)
  while 1
    let p = dir . '/' . ft . '.vim'
    if filereadable(p)
      source `=p`
      break
    endif
    if dir == g:persistent_savedir
      break
    endif
    let dir = fnamemodify(dir, ':h')
  endwhile
endfunction

function! s:Save(bufname)
  let ft = (&ft != '' ? &ft : '_')
  let dir = s:GetPath(a:bufname)
  let p = dir . '/' . ft . '.vim'
  let lines = []
  for opt in sort(g:persistent_options)
    call add(lines, printf("let %s = %s", opt, string(eval(opt))))
  endfor
  if !isdirectory(dir)
    call mkdir(dir, 'p')
  endif
  call writefile(lines, p)
endfunction

function! s:GetPath(bufname)
  let dir = fnamemodify(a:bufname, ':p:h')
  let dir = substitute(dir, '\\', '/', 'g')
  let dir = substitute(dir, '^\([^/]\):/', '/\1/', '')
  let dir = substitute(dir, '/$', '', '')
  return g:persistent_savedir . dir
endfunction

let s:save_cpo = &cpo
set cpo&vim

let &cpo = s:save_cpo
unlet s:save_cpo
