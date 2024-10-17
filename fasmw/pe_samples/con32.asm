format pe console
include 'win32ax.inc'

.data

_message db 'Hello World!',13,10
_message.len       = $ - _message

.code

begin:
        push    eax
        invoke  GetStdHandle,STD_OUTPUT_HANDLE
        mov     ecx,esp
        invoke  WriteFile,eax,_message,_message.len,ecx,0
        pop     eax
        invoke  ExitProcess,0

.end begin