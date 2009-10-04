" highlight unused/unassigned function local variable.
" Last Change: 2009-10-04

if exists("b:did_ftplugin")
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

hi default link PhpLocalVarCheckError Error

augroup PhpLocalVarCheck
  au! * <buffer>
  autocmd FileType <buffer> if &ft != 'php' | call s:Uninstall() | endif
  autocmd CursorMoved <buffer> call s:LocalVarCheck()
augroup END

function! s:Uninstall()
  au! PhpLocalVarCheck * <buffer>
  " TODO: How to remove variable from other window?
  unlet! w:php_localvarcheck_changedtick
  unlet! w:php_localvarcheck_funcstart
  unlet! w:php_localvarcheck_end
endfunction

function! s:LocalVarCheck()
  if get(w:, 'php_localvarcheck_changedtick', 0) == b:changedtick
        \ && get(w:, 'php_localvarcheck_funcstart', 0) <= line('.')
        \ && get(w:, 'php_localvarcheck_end', 0) >= line('.')
    return
  endif
  let view = winsaveview()
  let funcstart = search('\<function\>', 'bcW')
  let start = search('{', 'W')
  let end = searchpair('{', '', '}')
  call winrestview(view)
  if funcstart == 0 || start == 0 || end == 0 || end < line('.')
    call s:MatchDeleteGroup('PhpLocalVarCheckError')
    let w:php_localvarcheck_changedtick = b:changedtick
    let w:php_localvarcheck_funcstart = 0
    let w:php_localvarcheck_end = 0
  else
    let head = getline(funcstart, start)
    let body = getline(start + 1, end)
    let patterns = s:FindErrorVariable(head, body)
    call s:MatchDeleteGroup('PhpLocalVarCheckError')
    for pat in patterns
      call matchadd('PhpLocalVarCheckError', pat)
    endfor
    let w:php_localvarcheck_changedtick = b:changedtick
    let w:php_localvarcheck_funcstart = funcstart
    let w:php_localvarcheck_end = end
  endif
endfunction

function! s:FindErrorVariable(head, body)
  let args = s:MatchStrAll(join(a:head, "\n"), '\v\$\w+')
  let var_pat = '\c\v%(('
        \ .         '<as[ \t&]*'
        \ .   '|' . '<as[ \t&]*\$\w+\s*\=\>[ \t&]*'
        \ .   '|' . '<list\s*\([^)]*'
        \ .   '|' . '<global\s+[^;]*'
        \ .   '|' . '<static\s+[^;]*'
        \ . ')@<=)?(\$\w+)%((\s*\=[^=>])@=)?'
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
      " global variable may be used where somewhere else.
      if m[1] =~? '^global'
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
  for word in keys(assigned)
    if !has_key(used, word)
      call add(patterns, '\V' . escape(word, '\') . '\>')
    endif
  endfor
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

let &cpo = s:save_cpo
unlet s:save_cpo
