#include <windows.h>

#undef GetCurrentTime

#include <atomic>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Core.h>
#include <winrt/Windows.UI.Xaml.h>
#include <winrt/Windows.UI.Xaml.Controls.h>
#include <winrt/Windows.UI.Xaml.Controls.Primitives.h>
#include <winrt/Windows.UI.Xaml.Media.h>

namespace wf = winrt::Windows::Foundation;
namespace ws = winrt::Windows::System;
namespace wuc = winrt::Windows::UI::Core;
namespace wux = winrt::Windows::UI::Xaml;
namespace wuxc = winrt::Windows::UI::Xaml::Controls;
namespace wuxcp = winrt::Windows::UI::Xaml::Controls::Primitives;
namespace wuxm = winrt::Windows::UI::Xaml::Media;

struct PowerMenuEntry {
    const wchar_t* label;
    const wchar_t* glyph;
    const wchar_t* uri;
};

constexpr wchar_t kEntryTag[] = L"session-restore";
constexpr wchar_t kCallOnThreadMessage[] = L"SessionRestorePowerMenu_CallOnThread";
constexpr UINT_PTR kRetryTimerId = 0x53525057;

constexpr PowerMenuEntry kEntries[] = {
    {L"Save and shut down", L"", L"session-restore:shutdown"},
    {L"Save and restart", L"", L"session-restore:restart"},
};

std::atomic<bool> g_unloading = false;
std::atomic<bool> g_monitoring = false;
winrt::weak_ref<wuxc::MenuFlyout> g_flyout;
winrt::event_token g_openingToken{};
winrt::event_token g_visibilityToken{};

bool IsEntry(wuxc::MenuFlyoutItemBase const& item) {
    return winrt::unbox_value_or<winrt::hstring>(item.Tag(), L"") == kEntryTag;
}

void LaunchEntry(winrt::hstring const& uri) {
    try {
        ws::Launcher::LaunchUriAsync(wf::Uri(uri)).Completed([uri](auto&& operation, auto&&) {
            Wh_Log(L"launch %s: %d", uri.c_str(), operation.GetResults() ? 1 : 0);
        });
    } catch (winrt::hresult_error const& error) {
        Wh_Log(L"launch %s failed: 0x%08X", uri.c_str(), static_cast<unsigned>(error.code()));
    }
}

void RemoveEntries(wuxc::MenuFlyout const& flyout) {
    auto items = flyout.Items();
    for (int32_t index = static_cast<int32_t>(items.Size()) - 1; index >= 0; --index) {
        if (IsEntry(items.GetAt(index))) {
            items.RemoveAt(index);
        }
    }
}

void AddEntries(wuxc::MenuFlyout const& flyout) {
    RemoveEntries(flyout);
    auto items = flyout.Items();

    wuxc::MenuFlyoutSeparator separator;
    separator.Tag(winrt::box_value(winrt::hstring(kEntryTag)));
    items.Append(separator);

    for (auto const& entry : kEntries) {
        wuxc::FontIcon icon;
        icon.Glyph(entry.glyph);

        wuxc::MenuFlyoutItem item;
        item.Text(entry.label);
        item.Icon(icon);
        item.Tag(winrt::box_value(winrt::hstring(kEntryTag)));
        winrt::hstring uri = entry.uri;
        item.Click([uri](auto&&, auto&&) { LaunchEntry(uri); });
        items.Append(item);
    }
}

wux::FrameworkElement FindPowerButton(wux::DependencyObject const& parent) {
    int32_t count = wuxm::VisualTreeHelper::GetChildrenCount(parent);
    for (int32_t index = 0; index < count; ++index) {
        auto child = wuxm::VisualTreeHelper::GetChild(parent, index);
        if (auto element = child.try_as<wux::FrameworkElement>(); element && element.Name() == L"PowerButton") {
            return element;
        }
        if (auto found = FindPowerButton(child)) {
            return found;
        }
    }
    return nullptr;
}

wuxc::MenuFlyout FindPowerFlyout(wux::FrameworkElement const& powerButton) {
    if (auto named = powerButton.FindName(L"PowerButtonMenuFlyout")) {
        if (auto flyout = named.try_as<wuxc::MenuFlyout>()) {
            return flyout;
        }
    }
    if (auto button = powerButton.try_as<wuxc::Button>()) {
        if (auto attached = button.Flyout()) {
            if (auto flyout = attached.try_as<wuxc::MenuFlyout>()) {
                return flyout;
            }
        }
    }
    if (auto attached = wuxcp::FlyoutBase::GetAttachedFlyout(powerButton)) {
        return attached.try_as<wuxc::MenuFlyout>();
    }
    return nullptr;
}

void DetachFromPowerFlyout() {
    if (auto flyout = g_flyout.get()) {
        if (g_openingToken) {
            flyout.Opening(g_openingToken);
        }
        RemoveEntries(flyout);
    }
    g_openingToken = {};
    g_flyout = nullptr;
}

bool AttachToPowerFlyout() {
    if (g_unloading) {
        return false;
    }
    try {
        auto window = wux::Window::Current();
        auto content = window ? window.Content() : nullptr;
        auto powerButton = content ? FindPowerButton(content) : nullptr;
        auto flyout = powerButton ? FindPowerFlyout(powerButton) : nullptr;
        if (!flyout) {
            return false;
        }
        if (g_flyout.get() == flyout) {
            return true;
        }
        DetachFromPowerFlyout();
        g_openingToken = flyout.Opening([](auto&& sender, auto&&) {
            if (g_unloading) {
                return;
            }
            if (auto opened = sender.template try_as<wuxc::MenuFlyout>()) {
                AddEntries(opened);
            }
        });
        g_flyout = flyout;
        AddEntries(flyout);
        Wh_Log(L"attached to the power flyout");
        return true;
    } catch (winrt::hresult_error const& error) {
        Wh_Log(L"attach failed: 0x%08X", static_cast<unsigned>(error.code()));
        return false;
    }
}

void OnStartVisible() {
    if (g_unloading || g_flyout.get()) {
        return;
    }
    if (auto queue = ws::DispatcherQueue::GetForCurrentThread()) {
        queue.TryEnqueue(ws::DispatcherQueuePriority::Low, [] { AttachToPowerFlyout(); });
    }
}

bool StartMonitoring() {
    if (g_monitoring) {
        return true;
    }
    try {
        auto coreWindow = wuc::CoreWindow::GetForCurrentThread();
        if (!coreWindow) {
            return false;
        }
        g_visibilityToken = coreWindow.VisibilityChanged([](auto&&, auto&& args) {
            if (args.Visible()) {
                OnStartVisible();
            }
        });
        g_monitoring = true;
        if (coreWindow.Visible()) {
            OnStartVisible();
        }
        return true;
    } catch (...) {
        return false;
    }
}

void StopMonitoring() {
    try {
        if (auto coreWindow = wuc::CoreWindow::GetForCurrentThread(); coreWindow && g_visibilityToken) {
            coreWindow.VisibilityChanged(g_visibilityToken);
        }
    } catch (...) {
    }
    g_visibilityToken = {};
    try {
        DetachFromPowerFlyout();
    } catch (...) {
    }
    g_monitoring = false;
}

void StartMonitoringWithRetry(HWND window);

void CALLBACK RetryTimerProc(HWND window, UINT, UINT_PTR timerId, DWORD) {
    KillTimer(window, timerId);
    StartMonitoringWithRetry(window);
}

void StartMonitoringWithRetry(HWND window) {
    if (!g_unloading && !StartMonitoring()) {
        SetTimer(window, kRetryTimerId, 100, RetryTimerProc);
    }
}

bool IsCoreWindowClass(LPCWSTR className) {
    return className && (reinterpret_cast<ULONG_PTR>(className) & ~static_cast<ULONG_PTR>(0xffff)) != 0 &&
           _wcsicmp(className, L"Windows.UI.Core.CoreWindow") == 0;
}

using CreateWindowInBand_t = HWND(WINAPI*)(DWORD, LPCWSTR, LPCWSTR, DWORD, int, int, int, int, HWND, HMENU,
                                           HINSTANCE, PVOID, DWORD);
CreateWindowInBand_t CreateWindowInBand_Original;

HWND WINAPI CreateWindowInBand_Hook(DWORD exStyle, LPCWSTR className, LPCWSTR windowName, DWORD style, int x,
                                    int y, int width, int height, HWND parent, HMENU menu, HINSTANCE instance,
                                    PVOID param, DWORD band) {
    HWND window = CreateWindowInBand_Original(exStyle, className, windowName, style, x, y, width, height, parent,
                                              menu, instance, param, band);
    if (window && IsCoreWindowClass(className)) {
        StartMonitoringWithRetry(window);
    }
    return window;
}

using CreateWindowInBandEx_t = HWND(WINAPI*)(DWORD, LPCWSTR, LPCWSTR, DWORD, int, int, int, int, HWND, HMENU,
                                             HINSTANCE, PVOID, DWORD, DWORD);
CreateWindowInBandEx_t CreateWindowInBandEx_Original;

HWND WINAPI CreateWindowInBandEx_Hook(DWORD exStyle, LPCWSTR className, LPCWSTR windowName, DWORD style, int x,
                                      int y, int width, int height, HWND parent, HMENU menu, HINSTANCE instance,
                                      PVOID param, DWORD band, DWORD typeFlags) {
    HWND window = CreateWindowInBandEx_Original(exStyle, className, windowName, style, x, y, width, height, parent,
                                                menu, instance, param, band, typeFlags);
    if (window && IsCoreWindowClass(className)) {
        StartMonitoringWithRetry(window);
    }
    return window;
}

HWND FindCoreWindow() {
    HWND found = nullptr;
    EnumWindows(
        [](HWND window, LPARAM result) -> BOOL {
            DWORD processId = 0;
            if (!GetWindowThreadProcessId(window, &processId) || processId != GetCurrentProcessId()) {
                return TRUE;
            }
            WCHAR className[64]{};
            if (GetClassNameW(window, className, ARRAYSIZE(className)) && IsCoreWindowClass(className)) {
                *reinterpret_cast<HWND*>(result) = window;
                return FALSE;
            }
            return TRUE;
        },
        reinterpret_cast<LPARAM>(&found));
    return found;
}

using ThreadCall_t = void (*)(HWND);

struct ThreadCall {
    ThreadCall_t procedure;
    HWND window;
};

void CallOnWindowThread(HWND window, ThreadCall_t procedure) {
    DWORD threadId = GetWindowThreadProcessId(window, nullptr);
    if (!threadId) {
        return;
    }
    if (threadId == GetCurrentThreadId()) {
        procedure(window);
        return;
    }
    static const UINT message = RegisterWindowMessageW(kCallOnThreadMessage);
    HHOOK hook = SetWindowsHookExW(
        WH_CALLWNDPROC,
        [](int code, WPARAM wParam, LPARAM lParam) -> LRESULT {
            auto call = reinterpret_cast<const CWPSTRUCT*>(lParam);
            if (code == HC_ACTION && call->message == RegisterWindowMessageW(kCallOnThreadMessage)) {
                auto request = reinterpret_cast<ThreadCall*>(call->lParam);
                request->procedure(request->window);
            }
            return CallNextHookEx(nullptr, code, wParam, lParam);
        },
        nullptr, threadId);
    if (!hook) {
        return;
    }
    ThreadCall request{procedure, window};
    SendMessageW(window, message, 0, reinterpret_cast<LPARAM>(&request));
    UnhookWindowsHookEx(hook);
}

void HookUser32(const char* name, void* hook, void** original) {
    HMODULE user32 = LoadLibraryExW(L"user32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    void* target = user32 ? reinterpret_cast<void*>(GetProcAddress(user32, name)) : nullptr;
    if (target) {
        Wh_SetFunctionHook(target, hook, original);
    }
}

BOOL Wh_ModInit() {
    HookUser32("CreateWindowInBand", reinterpret_cast<void*>(CreateWindowInBand_Hook),
               reinterpret_cast<void**>(&CreateWindowInBand_Original));
    HookUser32("CreateWindowInBandEx", reinterpret_cast<void*>(CreateWindowInBandEx_Hook),
               reinterpret_cast<void**>(&CreateWindowInBandEx_Original));
    return TRUE;
}

void Wh_ModAfterInit() {
    if (HWND coreWindow = FindCoreWindow()) {
        CallOnWindowThread(coreWindow, [](HWND window) { StartMonitoringWithRetry(window); });
    }
}

void Wh_ModUninit() {
    g_unloading = true;
    if (HWND coreWindow = FindCoreWindow()) {
        CallOnWindowThread(coreWindow, [](HWND) { StopMonitoring(); });
    }
}
