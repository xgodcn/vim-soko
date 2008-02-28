
if exists("s:init")
  finish
endif
let s:init = 1

let s:dll = expand("<sfile>:p:h") . "/uim-ctl.so"
let s:direct_mode = ""
let s:current_mode = ""

augroup UimHelper
  au!
  autocmd InsertEnter * call s:RestoreMode()
  autocmd InsertLeave * call s:SaveMode()
  autocmd VimLeave * call libcall(s:dll, "unload", 0)
  " poll() does not work when dll is loaded before VimEnter.
  autocmd VimEnter * let s:err = libcall(s:dll, "load", s:dll)
  autocmd VimEnter * if s:err != "" | au! UimHelper * | endif
augroup END

function! s:GetProp()
  let buf = libcall(s:dll, "get_prop", 0)
  if buf =~ '^prop_list_update'
    let cur_method = matchstr(buf, 'action_imsw_\zs\w\+\ze\t\*')
    let current_mode = matchstr(buf, 'action_' . cur_method . '_\w*\ze\t\*')
    let direct_mode = matchstr(buf, 'action_' . cur_method . '_\%(direct\|latin\)')
    return [current_mode, direct_mode]
  endif
  return ["", ""]
endfunction

function! s:SaveMode()
  let [s:current_mode, s:direct_mode] = s:GetProp()
  if s:current_mode != ""
    call libcall(s:dll, "send_message", "prop_activate\n" . s:direct_mode . "\n")
  endif
endfunction

function! s:RestoreMode()
  if s:current_mode != ""
    call libcall(s:dll, "send_message", "prop_activate\n" . s:current_mode . "\n")
  endif
endfunction

