" Last Change: 2009-02-18

if exists("b:did_ftplugin")
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

" TODO: buffer local?
augroup PhpQuickCheck
  au!
  autocmd CursorMoved * if &ft == 'php' | call s:QuickCheck() | endif
  autocmd BufWritePost * if &ft == 'php' | call s:PhpLint() | endif
augroup END

hi default link MarkerError Error

function! s:PhpLint()
  if !executable('php')
    return
  endif
  let cmd = 'php -l ' . shellescape(expand('%'))
  let msg = system(cmd)
  if v:shell_error
    echoerr cmd
    echohl Error
    for line in split(msg, '\n')
      echomsg line
    endfor
    echohl None
  endif
endfunction

function! s:QuickCheck()
  if get(b:, 'php_quickcheck_changedtick', 0) != b:changedtick
        \ || get(b:, 'php_quickcheck_funcstart', 0) > line('.')
        \ || get(b:, 'php_quickcheck_end', 0) < line('.')
    let b:php_quickcheck_changedtick = b:changedtick
    call s:FindUndefinedVariable()
  endif
endfunction

function! s:FindUndefinedVariable()
  let view = winsaveview()
  let funcstart = search('^\s*\<function\>', 'bW')
  let start = search('{', 'W')
  let end = searchpair('{', '', '}')
  call winrestview(view)
  if funcstart == 0 || start == 0 || end == 0
    return
  endif
  let b:php_quickcheck_funcstart = funcstart
  let b:php_quickcheck_end = end
  if funcstart == start
    let start += 1
  endif
  call s:MatchDeleteGroup('MarkerError')
  let head = join(getline(funcstart, start - 1), "\n")
  let body = join(getline(start, end), "\n")
  let args = s:MatchListAll(head, '\v\$(\w+)')
  let vars = s:MatchListAll(body, '\c\v%((<as[ \t&]+|as[ \t&]\$\w+\s*\=\>[ \t&]*|<list\s*\([^)]*|<global\s+[^;]*)@<=)?(\$\w+)(\s*\=[^=])?')
  let special = s:CountWord(['$GLOBALS', '$_SERVER', '$_GET', '$_POST', '$_REQUEST', '$_FILES', '$_COOKIE', '$_SESSION', '$_ENV', "$this"])
  let assigned = s:CountWord(map(copy(args), 'v:val[0]'))
  let used = {}
  for m in vars
    let word = m[2]
    if has_key(special, word)
      continue
    endif
    if m[1] != '' || m[3] != ''
      let assigned[word] = 1
    else
      let used[word] = 1
      if !has_key(assigned, word)
        call matchadd('MarkerError', '\V' . escape(word, '\') . '\>')
      endif
    endif
  endfor
  for word in keys(filter(assigned, '!has_key(used, v:key)'))
    call matchadd('MarkerError', '\V' . escape(word, '\') . '\>')
  endfor
  if 0
  let keys = s:MatchListAll(body, '\v[''"](\w+)[''"]')
  let wordcounts = s:CountWord(map(copy(keys), 'v:val[0]'))
  for word in keys(filter(wordcounts, 'v:val == 1'))
    call matchadd('MarkerError', '\V' . escape(word, '\'))
  endfor
  endif
endfunction

function! s:CountWord(words)
  let wordcounts = {}
  for word in a:words
    let wordcounts[word] = get(wordcounts, word, 0) + 1
  endfor
  return wordcounts
endfunction

function! s:MatchListAll(text, pat)
  let matches = []
  call substitute(a:text, a:pat, '\=empty(add(matches, map(range(10), "submatch(v:val)")))', 'g')
  return matches
endfunction

function! s:MatchDeleteGroup(group)
  for m in getmatches()
    if m.group ==# a:group
      call matchdelete(m.id)
    endif
  endfor
endfunction

function! s:MatchExists(group)
  for m in getmatches()
    if m.group ==# a:group
      return 1
    endif
  endfor
  return 0
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
