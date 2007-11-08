/*
 * Usage:
 *   :echo libcall("mysystem.dll", "mysystem", "cmd.exe\ndir\n")
 *
 * Reference:
 *   http://support.microsoft.com/kb/190351/
 *
 * Only work for Gvim.
 *
 * XXX: no error handling
 */

#include <windows.h>
#include <stdlib.h>
#include <string.h>

struct iothread {
    BOOL bRunThread;
    HANDLE hThread;
    HANDLE fd;
    char *buf;
    size_t size;
};

static char *resultbuf = NULL;

const char * mysystem(char *args);

static HANDLE create_process(char *cmdline, HANDLE *in, HANDLE *out, HANDLE *err);
static DWORD WINAPI pipe_write(LPVOID lpParameter);
static DWORD WINAPI pipe_read(LPVOID lpParameter);

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved);

/* args = "cmdline\ninput-text" */
const char *
mysystem(char *args)
{
    char *cmdline;
    char *input;
    struct iothread io[3];
    HANDLE hProcess;
    HANDLE waitobj[4];
    DWORD ThreadId;

    cmdline = args;
    input = strchr(args, '\n');
    if (input != NULL)
        *input++ = 0;

    hProcess = create_process(cmdline, &io[0].fd, &io[1].fd, &io[2].fd);
    if (hProcess == NULL)
        return NULL;

    io[0].bRunThread = TRUE;
    io[0].buf = input;
    io[0].size = (input == NULL) ? 0 : strlen(input);
    io[0].hThread = CreateThread(NULL,0,pipe_write,(LPVOID)&io[0],0,&ThreadId);
    if (io[0].hThread == NULL)
        return NULL;

    io[1].bRunThread = TRUE;
    io[1].buf = NULL;
    io[1].size = 0;
    io[1].hThread = CreateThread(NULL,0,pipe_read,(LPVOID)&io[1],0,&ThreadId);
    if (io[1].hThread == NULL)
        return NULL;

    io[2].bRunThread = TRUE;
    io[2].buf = NULL;
    io[2].size = 0;
    io[2].hThread = CreateThread(NULL,0,pipe_read,(LPVOID)&io[2],0,&ThreadId);
    if (io[2].hThread == NULL)
        return NULL;

    waitobj[0] = io[0].hThread;
    waitobj[1] = io[1].hThread;
    waitobj[2] = io[2].hThread;
    waitobj[3] = hProcess;

    {
        MSG msg;
        int CTRL_C = 3;

        while (WaitForMultipleObjects(4, waitobj, TRUE, 50) == WAIT_TIMEOUT)
        {
            while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
            {
                TranslateMessage(&msg);
                DispatchMessage(&msg);
                if (msg.message == WM_CHAR && msg.wParam == CTRL_C)
                {
                    TerminateThread(io[0].hThread, 0);
                    TerminateThread(io[1].hThread, 0);
                    TerminateThread(io[2].hThread, 0);
                    TerminateProcess(hProcess, 0);
                    free(io[1].buf);
                    free(io[2].buf);
                    return NULL;
                }
            }
        }
    }

    io[0].bRunThread = FALSE;
    io[1].bRunThread = FALSE;
    io[2].bRunThread = FALSE;
    if (WaitForMultipleObjects(4, waitobj, TRUE, INFINITE) == WAIT_FAILED)
        return NULL;

    free(io[2].buf);

    resultbuf = io[1].buf;

    return resultbuf;
}

static HANDLE
create_process(char *cmdline, HANDLE *in, HANDLE *out, HANDLE *err)
{
    HANDLE hInputWriteTmp, hInputRead, hInputWrite;
    HANDLE hOutputReadTmp, hOutputRead, hOutputWrite;
    HANDLE hErrorReadTmp, hErrorRead, hErrorWrite;
    SECURITY_ATTRIBUTES sa;
    PROCESS_INFORMATION pi;
    STARTUPINFO si;

    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle = TRUE;

    if (!CreatePipe(&hInputRead, &hInputWriteTmp, &sa, 0))
        return NULL;
    if (!DuplicateHandle(GetCurrentProcess(), hInputWriteTmp, GetCurrentProcess(),
                &hInputWrite, 0, FALSE, DUPLICATE_SAME_ACCESS))
        return NULL;
    if (!CloseHandle(hInputWriteTmp))
        return NULL;

    if (!CreatePipe(&hOutputReadTmp, &hOutputWrite, &sa, 0))
        return NULL;
    if (!DuplicateHandle(GetCurrentProcess(), hOutputReadTmp, GetCurrentProcess(),
                &hOutputRead, 0, FALSE, DUPLICATE_SAME_ACCESS))
        return NULL;
    if (!CloseHandle(hOutputReadTmp))
        return NULL;

    if (!CreatePipe(&hErrorReadTmp, &hErrorWrite, &sa, 0))
        return NULL;
    if (!DuplicateHandle(GetCurrentProcess(), hErrorReadTmp, GetCurrentProcess(),
                &hErrorRead, 0, FALSE, DUPLICATE_SAME_ACCESS))
        return NULL;
    if (!CloseHandle(hErrorReadTmp))
        return NULL;

    ZeroMemory(&si, sizeof(STARTUPINFO));
    si.cb = sizeof(STARTUPINFO);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdInput = hInputRead;
    si.hStdOutput = hOutputWrite;
    si.hStdError = hErrorWrite;

    if (!CreateProcess(NULL, cmdline, NULL, NULL, TRUE,
                       CREATE_NEW_CONSOLE, NULL, NULL, &si, &pi))
        return NULL;

    if (!CloseHandle(pi.hThread))
        return NULL;

    if (!CloseHandle(hInputRead))
        return NULL;
    if (!CloseHandle(hOutputWrite))
        return NULL;
    if (!CloseHandle(hErrorWrite))
        return NULL;

    *in = hInputWrite;
    *out = hOutputRead;
    *err = hErrorRead;

    return pi.hProcess;
}

static
DWORD WINAPI pipe_write(LPVOID lpParameter)
{
    struct iothread *io = (struct iothread *)lpParameter;
    DWORD left = 0;
    DWORD nBytesWrote;

    while (io->bRunThread && left < io->size)
    {
        if (!WriteFile(io->fd,io->buf+left,io->size-left,&nBytesWrote,NULL))
        {
            if (GetLastError() == ERROR_NO_DATA)
                break; // Pipe was closed (normal exit path).
            else
                return -1;
        }
        left += nBytesWrote;
    }
    if (!CloseHandle(io->fd))
        return -1;
    return 1;
}

static
DWORD WINAPI pipe_read(LPVOID lpParameter)
{
    struct iothread *io = (struct iothread *)lpParameter;
    char tmp[512];
    DWORD nBytesRead;

    while (io->bRunThread)
    {
        if (!ReadFile(io->fd,tmp,sizeof(tmp),&nBytesRead,NULL) || !nBytesRead)
        {
            if (GetLastError() == ERROR_BROKEN_PIPE)
                break;
            else
                return -1;
        }
        io->buf = realloc(io->buf, io->size + nBytesRead);
        memmove(io->buf + io->size, tmp, nBytesRead);
        io->size += nBytesRead;
    }
    // NUL terminate
    io->buf = realloc(io->buf, io->size + 1);
    io->buf[io->size] = 0;

    if (!CloseHandle(io->fd))
        return -1;

    return 1;
}

BOOL WINAPI
DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved)
{
    switch( fdwReason )
    {
    case DLL_PROCESS_ATTACH:
        break;
    case DLL_PROCESS_DETACH:
        free(resultbuf);
        break;
    case DLL_THREAD_ATTACH:
        break;
    case DLL_THREAD_DETACH:
        break;
    }
    return TRUE;
}

