" Last Change: 2009-11-01

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
  let g:persistent_options = 'sw sts ts et'
endif

augroup PlugPersistent
  au!
  autocmd BufRead,BufNewFile * call s:OnEnter()
  autocmd BufLeave,BufUnload * call s:OnLeave()
augroup END

function! s:OnEnter()
  let ft = s:GetBufVar('&ft')
  if ft == ''
    let ft = '_'
  endif
  let dir = s:GetPath()
  while g:persistent_savedir <=? dir
    let p = dir . '/' . ft . '.vim'
    if filereadable(p)
      source `=p`
      break
    endif
    let dir = fnamemodify(dir, ':h')
  endwhile
endfunction

function! s:OnLeave()
  if !filereadable(expand('<afile>'))
    return
  endif
  let ft = s:GetBufVar('&ft')
  if ft == ''
    let ft = '_'
  endif
  let dir = s:GetPath()
  let p = dir . '/' . ft . '.vim'
  let lines = []
  for name in sort(split(g:persistent_options))
    call add(lines, printf("let %s = %s", name, string(s:GetBufVar('&' . name))))
  endfor
  if !isdirectory(dir)
    call mkdir(dir, 'p')
  endif
  call writefile(lines, p)
endfunction

function! s:GetPath()
  let dir = fnamemodify(expand('<afile>'), ':p:h')
  let dir = substitute(dir, '\\', '/', 'g')
  let dir = substitute(dir, '^\([^/]\):/', '/\1/', '')
  let dir = substitute(dir, '/$', '', '')
  return g:persistent_savedir . dir
endfunction

function! s:GetBufVar(varname)
  return getbufvar(str2nr(expand('<abuf>')), a:varname)
endfunction

let s:save_cpo = &cpo
set cpo&vim

let &cpo = s:save_cpo
unlet s:save_cpo
