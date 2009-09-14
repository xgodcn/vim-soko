" Last Change: 2009-09-14

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
  let opt = ''
  if get(g:, 'php_noShortTags', 0)
    let opt .= ' -d short_open_tag=0 '
  endif
  if get(g:, 'php_asp_tags', 0)
    let opt .= ' -d asp_tags=1 '
  endif
  let cmd = 'php -l ' . opt . shellescape(expand('%'))
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

function! s:QuickCheck()
  if get(w:, 'php_quickcheck_changedtick', 0) == b:changedtick
        \ && get(w:, 'php_quickcheck_funcstart', 0) <= line('.')
        \ && get(w:, 'php_quickcheck_end', 0) >= line('.')
    return
  endif
  let view = winsaveview()
  let funcstart = search('\<function\>', 'bcW')
  let start = search('{', 'W')
  let end = searchpair('{', '', '}')
  call winrestview(view)
  if funcstart == 0 || start == 0 || end == 0 || end < line('.')
    call s:MatchDeleteGroup('MarkerError')
    let w:php_quickcheck_changedtick = b:changedtick
    let w:php_quickcheck_funcstart = 0
    let w:php_quickcheck_end = 0
  else
    let head = getline(funcstart, start)
    let body = getline(start + 1, end)
    let patterns = s:FindUndefinedVariable(head, body)
    call s:MatchDeleteGroup('MarkerError')
    for pat in patterns
      call matchadd('MarkerError', pat)
    endfor
    let w:php_quickcheck_changedtick = b:changedtick
    let w:php_quickcheck_funcstart = funcstart
    let w:php_quickcheck_end = end
  endif
endfunction

function! s:FindUndefinedVariable(head, body)
  let args = s:MatchStrAll(join(a:head, "\n"), '\v\$\w+')
  let var_pat = '\c\v%((<as[ \t&]*|as[ \t&]*\$\w+\s*\=\>[ \t&]*|<list\s*\([^)]*|<global\s+[^;]*|<static\s+[^;]*)@<=)?(\$\w+)%((\s*\=[^=>])@=)?'
  " XXX: s:MatchListAll(join(a:body, "\n"), var_pat) is slow for long
  " a:body because of @<= pattern.  Parse it by line.
  let vars = []
  for line in a:body
    call extend(vars, s:MatchListAll(line, var_pat))
  endfor
  let special = s:CountWord(['$GLOBALS', '$_SERVER', '$_GET', '$_POST', '$_REQUEST', '$_FILES', '$_COOKIE', '$_SESSION', '$_ENV', "$this"])
  let assigned = s:CountWord(args)
  let global = {}
  let used = {}
  let patterns = []
  for m in vars
    let word = m[2]
    if has_key(special, word)
      continue
    endif
    if m[1] != '' || m[3] != ''
      let assigned[word] = 1
      " global variable may be used somewhere else.
      if m[1] =~ '^global'
        let global[word] = 1
      elseif has_key(global, word)
        let used[word] = 1
      endif
    else
      let used[word] = 1
      if !has_key(assigned, word)
        call add(patterns, '\V' . escape(word, '\') . '\>')
      endif
    endif
  endfor
  for word in keys(filter(assigned, '!has_key(used, v:key)'))
    call add(patterns, '\V' . escape(word, '\') . '\>')
  endfor
  if 0
  let keys = s:MatchListAll(body, '\v[''"](\w+)[''"]')
  let wordcounts = s:CountWord(map(copy(keys), 'v:val[0]'))
  for word in keys(filter(wordcounts, 'v:val == 1'))
    call add(patterns, '\V' . escape(word, '\'))
  endfor
  endif
  return patterns
endfunction

function! s:CountWord(words)
  let wordcounts = {}
  for word in a:words
    let wordcounts[word] = get(wordcounts, word, 0) + 1
  endfor
  return wordcounts
endfunction

function! s:MatchStrAll(text, pat)
  let matches = []
  call substitute(a:text, a:pat, '\=empty(add(matches, submatch(0)))', 'g')
  return matches
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

function! s:EchoHlMsg(hlgroup, msg)
  execute 'echohl ' . a:hlgroup
  for line in split(a:msg, '\n')
    echomsg line
  endfor
  echohl None
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
