#include <windows.h>

#undef GetCurrentTime

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <string>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Core.h>
#include <winrt/Windows.UI.Xaml.h>
#include <winrt/Windows.UI.Xaml.Controls.h>
#include <winrt/Windows.UI.Xaml.Controls.Primitives.h>
#include <winrt/Windows.UI.Xaml.Input.h>
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

void Trace(const wchar_t* format, ...) {
    wchar_t message[1024];
    va_list arguments;
    va_start(arguments, format);
    _vsnwprintf_s(message, _TRUNCATE, format, arguments);
    va_end(arguments);
    Wh_Log(L"%s", message);

    wchar_t path[MAX_PATH];
    DWORD length = GetTempPathW(MAX_PATH, path);
    if (!length || length + 32 >= MAX_PATH) {
        return;
    }
    wcscat_s(path, L"session-restore-power-menu.log");
    HANDLE file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t line[1100];
    int lineLength = swprintf_s(line, L"%02u:%02u:%02u %s\r\n", now.wHour, now.wMinute, now.wSecond, message);
    char utf8[3300];
    int bytes = WideCharToMultiByte(CP_UTF8, 0, line, lineLength, utf8, sizeof(utf8), nullptr, nullptr);
    DWORD written = 0;
    WriteFile(file, utf8, bytes, &written, nullptr);
    CloseHandle(file);
}

std::wstring DescribeItems(winrt::Windows::Foundation::Collections::IVector<wuxc::MenuFlyoutItemBase> const& items) {
    std::wstring description;
    for (auto const& item : items) {
        description += winrt::get_class_name(item).c_str();
        if (auto menuItem = item.try_as<wuxc::MenuFlyoutItem>()) {
            description += L"('";
            description += menuItem.Text().c_str();
            description += L"')";
        }
        description += item.Visibility() == wux::Visibility::Visible ? L" " : L"[hidden] ";
    }
    return description;
}

bool IsEntry(wuxc::MenuFlyoutItemBase const& item) {
    return winrt::unbox_value_or<winrt::hstring>(item.Tag(), L"") == kEntryTag;
}

void LaunchEntry(winrt::hstring const& uri) {
    try {
        ws::Launcher::LaunchUriAsync(wf::Uri(uri)).Completed([uri](auto&& operation, auto&&) {
            Trace(L"launch %s: %d", uri.c_str(), operation.GetResults() ? 1 : 0);
        });
    } catch (winrt::hresult_error const& error) {
        Trace(L"launch %s failed: 0x%08X", uri.c_str(), static_cast<unsigned>(error.code()));
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

wuxc::MenuFlyout FlyoutNamedFrom(wux::FrameworkElement const& element) {
    if (auto named = element.FindName(L"PowerButtonMenuFlyout")) {
        return named.try_as<wuxc::MenuFlyout>();
    }
    return nullptr;
}

wuxc::MenuFlyout FlyoutOn(wux::FrameworkElement const& element) {
    if (auto button = element.try_as<wuxc::Button>()) {
        if (auto attached = button.Flyout()) {
            if (auto flyout = attached.try_as<wuxc::MenuFlyout>()) {
                return flyout;
            }
        }
    }
    if (auto attached = wuxcp::FlyoutBase::GetAttachedFlyout(element)) {
        return attached.try_as<wuxc::MenuFlyout>();
    }
    return nullptr;
}

wuxc::MenuFlyout FindFlyoutBelow(wux::DependencyObject const& parent, int depth) {
    if (depth > 12) {
        return nullptr;
    }
    int32_t count = wuxm::VisualTreeHelper::GetChildrenCount(parent);
    for (int32_t index = 0; index < count; ++index) {
        auto child = wuxm::VisualTreeHelper::GetChild(parent, index);
        if (auto element = child.try_as<wux::FrameworkElement>()) {
            if (auto flyout = FlyoutOn(element)) {
                Trace(L"flyout found on %s '%s'", winrt::get_class_name(element).c_str(), element.Name().c_str());
                return flyout;
            }
            if (auto flyout = FlyoutNamedFrom(element)) {
                Trace(L"flyout found by name from %s '%s'", winrt::get_class_name(element).c_str(),
                      element.Name().c_str());
                return flyout;
            }
        }
        if (auto flyout = FindFlyoutBelow(child, depth + 1)) {
            return flyout;
        }
    }
    return nullptr;
}

wuxc::MenuFlyout FindPowerFlyout(wux::FrameworkElement const& powerButton) {
    if (auto flyout = FlyoutOn(powerButton)) {
        Trace(L"flyout found on the PowerButton element");
        return flyout;
    }
    if (auto userControl = powerButton.try_as<wuxc::UserControl>()) {
        if (auto content = userControl.Content().try_as<wux::FrameworkElement>()) {
            if (auto flyout = FlyoutNamedFrom(content)) {
                Trace(L"flyout found by name from the view content");
                return flyout;
            }
        }
    }
    if (auto flyout = FindFlyoutBelow(powerButton, 0)) {
        return flyout;
    }
    Trace(L"no flyout under PowerButton (%s)", winrt::get_class_name(powerButton).c_str());
    return nullptr;
}

void DescribeOpenPopups() {
    try {
        auto popups = wuxm::VisualTreeHelper::GetOpenPopups(wux::Window::Current());
        Trace(L"open popups: %u", popups.Size());
        for (auto const& popup : popups) {
            auto child = popup.Child();
            Trace(L"popup child: %s", child ? winrt::get_class_name(child).c_str() : L"none");
            if (auto presenter = child ? child.try_as<wuxc::MenuFlyoutPresenter>() : nullptr) {
                std::wstring texts;
                for (auto const& item : presenter.Items()) {
                    texts += winrt::get_class_name(item).c_str();
                    if (auto menuItem = item.try_as<wuxc::MenuFlyoutItem>()) {
                        texts += L"('";
                        texts += menuItem.Text().c_str();
                        texts += L"')";
                    }
                    texts += L" ";
                }
                Trace(L"presenter items: %s", texts.c_str());
            }
        }
    } catch (winrt::hresult_error const& error) {
        Trace(L"describe popups failed: 0x%08X", static_cast<unsigned>(error.code()));
    }
}

wux::Input::PointerEventHandler g_releasedHandler{nullptr};
winrt::weak_ref<wux::FrameworkElement> g_powerButton;

void UnwatchPowerButton() {
    if (auto powerButton = g_powerButton.get(); powerButton && g_releasedHandler) {
        powerButton.RemoveHandler(wux::UIElement::PointerReleasedEvent(), winrt::box_value(g_releasedHandler));
    }
    g_releasedHandler = nullptr;
    g_powerButton = nullptr;
}

void WatchPowerButton(wux::FrameworkElement const& powerButton) {
    if (g_powerButton.get() == powerButton) {
        return;
    }
    UnwatchPowerButton();
    g_releasedHandler = wux::Input::PointerEventHandler([](auto&&, auto&&) {
        Trace(L"power button released");
        if (auto queue = ws::DispatcherQueue::GetForCurrentThread()) {
            queue.TryEnqueue(ws::DispatcherQueuePriority::Low, [] { DescribeOpenPopups(); });
        }
    });
    powerButton.AddHandler(wux::UIElement::PointerReleasedEvent(), winrt::box_value(g_releasedHandler), true);
    g_powerButton = powerButton;
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
    UnwatchPowerButton();
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
                Trace(L"opening, same flyout: %d, items before: %s", opened == g_flyout.get() ? 1 : 0,
                      DescribeItems(opened.Items()).c_str());
                AddEntries(opened);
                Trace(L"opening, items after: %s", DescribeItems(opened.Items()).c_str());
            }
        });
        g_flyout = flyout;
        WatchPowerButton(powerButton);
        AddEntries(flyout);
        Trace(L"attached, items: %s", DescribeItems(flyout.Items()).c_str());
        return true;
    } catch (winrt::hresult_error const& error) {
        Trace(L"attach failed: 0x%08X", static_cast<unsigned>(error.code()));
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
