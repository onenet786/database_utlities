#ifndef WIN=======
#ifndef WIN32_WINDOW32_WINDOW_H_
#define WIN_H_
#define WIN32_WINDOW32_WINDOW_H_

#include <_H_

#include <windows.h>

classwindows.h>

class Win32Window {
 Win32Window {
 public:
  // public:
  // Constructor and other methods Constructor and other methods here

  // here

  // Return a RECT Return a RECT representing the bounds of representing the bounds of the current client area the current client area.
  RECT.
  RECT GetClientArea();

 GetClientArea();

 protected:
  // protected:
  // Processes and route salient Processes and route salient window messages for mouse window messages for mouse handling,
  // handling,
  // size change and D size change and DPI. DelegatesPI. Delegates handling of these to handling of these to member overloads that member overloads that
  // inher
  // inheriting classes can handleiting classes can handle.
  virtual L.
  virtual LRESULT MessageHandlerRESULT MessageHandler(HWND window(HWND window,
                                 UINT,
                                 UINT const message,
                                 const message,
                                 WPARAM const WPARAM const wparam,
                                 wparam,
                                 LPARAM const LPARAM const lparam) noexcept lparam) noexcept;
  friend class;
  friend class WindowClassRegist WindowClassRegistrar;

  //rar;

  // OS callback called by OS callback called by message pump. Hand message pump. Handles the WM_Nles the WM_NCCREATE messageCCREATE message which
  // which
  // is passed when the is passed when the non-client area is non-client area is being created and enables being created and enables automatic
  // automatic
  // non-client DPI non-client DPI scaling so that the scaling so that the non-client area automatically non-client area automatically
  // responds
  // responds to changes in D to changes in DPI. All otherPI. All other messages are handled by messages are handled by
  // Message
  // MessageHandler.
  staticHandler.
  static LRESULT CALL LRESULT CALLBACK WndProcBACK WndProc(HWND const(HWND const window,
                                  U window,
                                  UINT const message,
INT const message,
                                  WPARAM                                  WPARAM const wparam,
 const wparam,
                                  LPARAM                                  LPARAM const lparam) const lparam) noexcept;
};

#endif noexcept;
};

#endif  // WIN32  // WIN32_WINDOW_H_WINDOW_H_
>>>>>>>_
