#include <windows.h>
#include <shellapi.h>

#define LISTENER_CLASS L"SessionRestorePowerMenuListener"
#define LISTENER_MESSAGE L"SessionRestorePowerMenu_Execute"
#define ACTION_SHUTDOWN 0
#define ACTION_RESTART 1

static UINT g_message;
static wchar_t g_repository[MAX_PATH];

static void RunSaveScript(WPARAM action) {
    wchar_t system[MAX_PATH];
    wchar_t commandLine[4 * MAX_PATH];
    GetSystemDirectoryW(system, MAX_PATH);
    wsprintfW(commandLine, L"\"%s\\wscript.exe\" \"%s\\Hidden.vbs\" \"%s\\Save-AndShutdown.ps1\"%s", system,
              g_repository, g_repository, action == ACTION_RESTART ? L" \"-Restart\"" : L"");
    STARTUPINFOW startup = {sizeof(startup)};
    PROCESS_INFORMATION process;
    if (CreateProcessW(NULL, commandLine, NULL, NULL, FALSE, 0, NULL, g_repository, &startup, &process)) {
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    }
}

static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (g_message && message == g_message) {
        if (wParam == ACTION_SHUTDOWN || wParam == ACTION_RESTART) {
            RunSaveScript(wParam);
        }
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR arguments, int show) {
    int count = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!argv || count < 2) {
        return 2;
    }
    lstrcpynW(g_repository, argv[1], MAX_PATH);
    LocalFree(argv);

    HANDLE mutex = CreateMutexW(NULL, TRUE, L"Local\\" LISTENER_CLASS);
    if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS) {
        return 0;
    }

    g_message = RegisterWindowMessageW(LISTENER_MESSAGE);
    WNDCLASSEXW windowClass = {sizeof(windowClass)};
    windowClass.lpfnWndProc = WindowProc;
    windowClass.hInstance = instance;
    windowClass.lpszClassName = LISTENER_CLASS;
    if (!RegisterClassExW(&windowClass)) {
        return 1;
    }
    HWND window = CreateWindowExW(0, LISTENER_CLASS, LISTENER_CLASS, 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, instance, NULL);
    if (!window) {
        return 1;
    }
    ChangeWindowMessageFilterEx(window, g_message, MSGFLT_ALLOW, NULL);

    MSG message;
    while (GetMessageW(&message, NULL, 0, 0) > 0) {
        DispatchMessageW(&message);
    }
    return 0;
}
