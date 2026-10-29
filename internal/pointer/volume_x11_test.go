//go:build linux

package pointer

import (
 "github.com/jezek/xgb"
 "github.com/jezek/xgb/xproto"
 "os"
 "testing"
 "time"
)

func TestVolumeX11Integration(t *testing.T) {
 if os.Getenv("LINKPAD_X11_INTEGRATION")!="1" {t.Skip("requires isolated Xvfb")}
 conn,err:=xgb.NewConn();if err!=nil{t.Fatal(err)};defer conn.Close()
 setup:=xproto.Setup(conn);screen:=setup.DefaultScreen(conn)
 window,err:=xproto.NewWindowId(conn);if err!=nil{t.Fatal(err)}
 if err:=xproto.CreateWindowChecked(conn,screen.RootDepth,window,screen.Root,0,0,200,200,0,xproto.WindowClassInputOutput,screen.RootVisual,xproto.CwEventMask,[]uint32{xproto.EventMaskKeyPress|xproto.EventMaskKeyRelease}).Check();err!=nil{t.Fatal(err)}
 defer xproto.DestroyWindow(conn,window)
 if err:=xproto.MapWindowChecked(conn,window).Check();err!=nil{t.Fatal(err)}
 if err:=xproto.SetInputFocusChecked(conn,xproto.InputFocusPointerRoot,window,xproto.TimeCurrentTime).Check();err!=nil{t.Fatal(err)}
 mapping,err:=xproto.GetKeyboardMapping(conn,setup.MinKeycode,byte(int(setup.MaxKeycode)-int(setup.MinKeycode)+1)).Reply();if err!=nil{t.Fatal(err)}
 for _,action:=range []string{"down","mute","up"}{if err:=nativeVolume(action);err!=nil{t.Fatal(err)}}
 var symbols []xproto.Keysym
 releases:=0
 deadline:=time.Now().Add(2*time.Second)
 for time.Now().Before(deadline)&&releases<3 {
  event,err:=conn.PollForEvent();if err!=nil{t.Fatal(err)}
  switch e:=event.(type) {
  case xproto.KeyPressEvent:
   index:=(int(e.Detail)-int(setup.MinKeycode))*int(mapping.KeysymsPerKeycode)
   symbols=append(symbols,mapping.Keysyms[index])
   if e.State&(xproto.ModMaskShift|xproto.ModMaskControl|xproto.ModMask1|xproto.ModMask4)!=0{t.Fatal("volume inherited keyboard modifiers")}
  case xproto.KeyReleaseEvent: releases++
  }
  time.Sleep(time.Millisecond)
 }
 if releases!=3 || len(symbols)!=3 || symbols[0]!=0x1008ff11 || symbols[1]!=0x1008ff12 || symbols[2]!=0x1008ff13 {t.Fatalf("wrong media events: %x releases=%d",symbols,releases)}
}
