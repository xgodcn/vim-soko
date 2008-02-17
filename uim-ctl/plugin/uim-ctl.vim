" 2007-01-30

if exists("s:init")
  finish
endif
let s:init = 1

let s:dll = expand("<sfile>:p:h") . "/uim-ctl.so"
let s:direct_mode = ""
let s:current_mode = ""

call libcall(s:dll, "load", s:dll)

augroup UimHelper
  au!
  autocmd InsertEnter * call s:RestoreMode()
  autocmd InsertLeave * call s:SaveMode()
  autocmd CursorHold,CursorHoldI * call s:PumpEvent()
augroup END

function! s:PumpEvent()
  let buf = libcall(s:dll, "pump_event", 0)
  if buf =~ '^prop_list_update'
    let cur_method = matchstr(buf, 'action_imsw_\zs\w\+\ze\t\*')
    let current_mode = matchstr(buf, 'action_' . cur_method . '_\w*\ze\t\*')
    let direct_mode = matchstr(buf, 'action_' . cur_method . '_\%(direct\|latin\)')
    return [current_mode, direct_mode]
  endif
  return ["", ""]
endfunction

function! s:SaveMode()
  let [s:current_mode, s:direct_mode] = s:PumpEvent()
  if s:current_mode != ""
    call libcall(s:dll, "send_message", "prop_activate\n" . s:direct_mode . "\n")
  endif
endfunction

function! s:RestoreMode()
  if s:current_mode != ""
    call libcall(s:dll, "send_message", "prop_activate\n" . s:current_mode . "\n")
  endif
  call s:PumpEvent()
endfunction

