//! Minimal Win32 bindings for window + GDI + time.
//! Avoids @cImport so we don't depend on mingw headers.

pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HBITMAP = ?*anyopaque;
pub const HGDIOBJ = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const LPVOID = ?*anyopaque;
pub const LPCWSTR = [*:0]const u16;
pub const LPWSTR = [*]u16;
pub const BOOL = i32;
pub const UINT = c_uint;
pub const DWORD = u32;
pub const WORD = u16;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const LONG = c_long;
pub const ATOM = WORD;
pub const HANDLE = ?*anyopaque;

pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: ?*anyopaque,
    hCursor: ?*anyopaque,
    hbrBackground: ?*anyopaque,
    lpszMenuName: ?LPCWSTR,
    lpszClassName: LPCWSTR,
    hIconSm: ?*anyopaque,
};

pub const POINT = extern struct { x: LONG, y: LONG };
pub const MSG = extern struct {
    hwnd: HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};
pub const RECT = extern struct { left: LONG, top: LONG, right: LONG, bottom: LONG };
pub const LARGE_INTEGER = extern union { QuadPart: i64, u: extern struct { LowPart: DWORD, HighPart: LONG } };

pub const CS_HREDRAW = 0x0002;
pub const CS_VREDRAW = 0x0001;
pub const CS_OWNDC = 0x0020;

pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));

pub const SW_SHOW: i32 = 5;

pub const WM_DESTROY: UINT = 0x0002;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_KEYUP: UINT = 0x0101;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_QUIT: UINT = 0x0012;
pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_MOUSEWHEEL: UINT = 0x020A;
pub const WHEEL_DELTA: i16 = 120;

pub const VK_SPACE: usize = 0x20;
pub const VK_ESCAPE: usize = 0x1B;
pub const VK_UP: usize = 0x26;
pub const VK_W: usize = 0x57;
pub const VK_R: usize = 0x52;

pub const PM_REMOVE: UINT = 0x0001;

pub const SRCCOPY: DWORD = 0x00CC0020;
pub const IDC_ARROW: usize = 32512;

pub const COLOR_WINDOW: i32 = 5;

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.winapi) HINSTANCE;
pub extern "kernel32" fn QueryPerformanceCounter(lpPerformanceCount: *LARGE_INTEGER) callconv(.winapi) BOOL;
pub extern "kernel32" fn QueryPerformanceFrequency(lpFrequency: *LARGE_INTEGER) callconv(.winapi) BOOL;
pub extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(.winapi) void;

pub extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: LPCWSTR, lpWindowName: LPCWSTR, dwStyle: DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: LPVOID) callconv(.winapi) HWND;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD) callconv(.winapi) BOOL;
pub extern "user32" fn LoadCursorW(hInstance: HINSTANCE, lpCursorName: LPCWSTR) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn GetDC(hWnd: HWND) callconv(.winapi) HDC;
pub extern "user32" fn ReleaseDC(hWnd: HWND, hDC: HDC) callconv(.winapi) i32;
pub extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;

pub extern "gdi32" fn CreateCompatibleDC(hdc: HDC) callconv(.winapi) HDC;
pub extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, nWidth: i32, nHeight: i32) callconv(.winapi) HBITMAP;
pub extern "gdi32" fn SelectObject(hdc: HDC, hgdiobj: HGDIOBJ) callconv(.winapi) HGDIOBJ;
pub extern "gdi32" fn DeleteObject(hObject: HGDIOBJ) callconv(.winapi) BOOL;
pub extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn BitBlt(hdcDest: HDC, nXDest: i32, nYDest: i32, nWidth: i32, nHeight: i32, hdcSrc: HDC, nXSrc: i32, nYSrc: i32, dwRop: DWORD) callconv(.winapi) BOOL;
pub extern "gdi32" fn CreateSolidBrush(crColor: DWORD) callconv(.winapi) HBRUSH;
pub extern "gdi32" fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.winapi) i32;
pub extern "gdi32" fn Rectangle(hdc: HDC, nLeftRect: i32, nTopRect: i32, nRightRect: i32, nBottomRect: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn Ellipse(hdc: HDC, nLeftRect: i32, nTopRect: i32, nRightRect: i32, nBottomRect: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn SetBkMode(hdc: HDC, iBkMode: i32) callconv(.winapi) i32;
pub extern "gdi32" fn SetTextColor(hdc: HDC, crColor: DWORD) callconv(.winapi) DWORD;
pub extern "gdi32" fn TextOutW(hdc: HDC, nXStart: i32, nYStart: i32, lpString: LPCWSTR, cbString: i32) callconv(.winapi) BOOL;
pub extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) i32;
pub extern "gdi32" fn SetPixelFormat(hdc: HDC, iPixelFormat: i32, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) BOOL;
pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) BOOL;

pub extern "winmm" fn timeBeginPeriod(uPeriod: UINT) callconv(.winapi) UINT;

// WGL / opengl32
pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) ?*anyopaque;
pub extern "opengl32" fn wglMakeCurrent(hdc: HDC, hglrc: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "opengl32" fn wglDeleteContext(hglrc: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "opengl32" fn wglGetProcAddress(lpszProc: [*:0]const u8) callconv(.winapi) ?*anyopaque;

// Minimal gl for legacy fallback (opengl32 exports these)
pub extern "opengl32" fn glClearColor(red: f32, green: f32, blue: f32, alpha: f32) callconv(.winapi) void;
pub extern "opengl32" fn glClear(mask: DWORD) callconv(.winapi) void;
pub extern "opengl32" fn glViewport(x: i32, y: i32, width: i32, height: i32) callconv(.winapi) void;
pub extern "opengl32" fn glEnable(cap: DWORD) callconv(.winapi) void;
pub extern "opengl32" fn glBlendFunc(sfactor: DWORD, dfactor: DWORD) callconv(.winapi) void;
pub extern "opengl32" fn glGetString(name: DWORD) callconv(.winapi) ?[*:0]const u8;

pub const PFD_DRAW_TO_WINDOW: DWORD = 0x00000004;
pub const PFD_SUPPORT_OPENGL: DWORD = 0x00000020;
pub const PFD_DOUBLEBUFFER: DWORD = 0x00000001;
pub const PFD_TYPE_RGBA: u8 = 0;
pub const PFD_MAIN_PLANE: u8 = 0;

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 1,
    dwFlags: DWORD,
    iPixelType: u8,
    cColorBits: u8,
    cRedBits: u8 = 0,
    cRedShift: u8 = 0,
    cGreenBits: u8 = 0,
    cGreenShift: u8 = 0,
    cBlueBits: u8 = 0,
    cBlueShift: u8 = 0,
    cAlphaBits: u8 = 0,
    cAlphaShift: u8 = 0,
    cAccumBits: u8 = 0,
    cAccumRedBits: u8 = 0,
    cAccumGreenBits: u8 = 0,
    cAccumBlueBits: u8 = 0,
    cAccumAlphaBits: u8 = 0,
    cDepthBits: u8,
    cStencilBits: u8,
    cAuxBuffers: u8 = 0,
    iLayerType: u8,
    bReserved: u8 = 0,
    dwLayerMask: DWORD = 0,
    dwVisibleMask: DWORD = 0,
    dwDamageMask: DWORD = 0,
};

// GL constants
pub const GL_COLOR_BUFFER_BIT: DWORD = 0x00004000;
pub const GL_BLEND: DWORD = 0x0BE2;
pub const GL_SRC_ALPHA: DWORD = 0x0302;
pub const GL_ONE_MINUS_SRC_ALPHA: DWORD = 0x0303;
pub const GL_VERSION: DWORD = 0x1F02;

// Re-export wrappers for easy use
pub const Win32 = struct {
    pub const getModuleHandleW = GetModuleHandleW;
    pub const queryPerformanceCounter = QueryPerformanceCounter;
    pub const queryPerformanceFrequency = QueryPerformanceFrequency;
    pub const sleep = Sleep;
    pub const registerClassExW = RegisterClassExW;
    pub const createWindowExW = CreateWindowExW;
    pub const defWindowProcW = DefWindowProcW;
    pub const showWindow = ShowWindow;
    pub const updateWindow = UpdateWindow;
    pub const peekMessageW = PeekMessageW;
    pub const translateMessage = TranslateMessage;
    pub const dispatchMessageW = DispatchMessageW;
    pub const postQuitMessage = PostQuitMessage;
    pub const destroyWindow = DestroyWindow;
    pub const getClientRect = GetClientRect;
    pub const adjustWindowRectEx = AdjustWindowRectEx;
    pub const loadCursorW = LoadCursorW;
    pub const getDC = GetDC;
    pub const releaseDC = ReleaseDC;
    pub const createCompatibleDC = CreateCompatibleDC;
    pub const createCompatibleBitmap = CreateCompatibleBitmap;
    pub const selectObject = SelectObject;
    pub const deleteObject = DeleteObject;
    pub const deleteDC = DeleteDC;
    pub const bitBlt = BitBlt;
    pub const createSolidBrush = CreateSolidBrush;
    pub const fillRect = FillRect;
    pub const rectangle = Rectangle;
    pub const ellipse = Ellipse;
};
