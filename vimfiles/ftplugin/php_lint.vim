" execute lint at write.
" Last Change: 2009-10-04

if exists("b:did_ftplugin")
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

if !exists('g:php_lint_cmd')
  let g:php_lint_cmd = 'php -l {file}'
endif
if !exists('b:php_lint_cmd')
  let b:php_lint_cmd = g:php_lint_cmd
endif

augroup PhpLint
  au! * <buffer>
  autocmd FileType <buffer> if &ft != 'php' | call s:Uninstall() | endif
  autocmd BufWritePost <buffer> call s:PhpLint()
augroup END

function! s:Uninstall()
  au! PhpLint * <buffer>
  unlet b:php_lint_cmd
endfunction

function! s:PhpLint()
  if !executable('php')
    return
  endif
  let file = shellescape(expand('%'))
  let cmd = get(b:, 'php_lint_cmd', g:php_lint_cmd)
  let cmd = substitute(cmd, '{\(\w\+\)}', '\=eval(submatch(1))', 'g')
  let msg = system(cmd)
  " XXX: sometimes php returns error code "139" with no syntax error
  if msg =~ 'No syntax errors detected in'
    return
  endif
  if v:shell_error
    echoerr cmd
    call s:EchoHlMsg('Error', msg)
  endif
endfunction

function! s:EchoHlMsg(hlgroup, msg)
  execute 'echohl ' . a:hlgroup
  for line in split(a:msg, '\n')
    echomsg line
  endfor
  echohl None
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
