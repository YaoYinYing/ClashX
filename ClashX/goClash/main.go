package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Foundation
#import <Foundation/Foundation.h>
#include <stdlib.h>
#import "UIHelper.h"
*/
import "C"

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unsafe"

	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var secretOverride string = ""
var enableIPV6 bool = false
var smartLightGBMOverride bool = false
var smartLightGBMURL string = ""
var smartLightGBMAutoUpdate bool = false
var smartLightGBMUpdateInterval int = 72

func isAddrValid(addr string) bool {
	if addr != "" {
		comps := strings.Split(addr, ":")
		v := comps[len(comps)-1]
		if port, err := strconv.Atoi(v); err == nil {
			if port > 0 && port < 65535 {
				return checkPortAvailable(port)
			}
		}
	}
	return false
}

func checkPortAvailable(port int) bool {
	if port < 1 || port > 65534 {
		return false
	}
	addr := ":"
	l, err := net.Listen("tcp", addr+strconv.Itoa(port))
	if err != nil {
		log.Warnln("check port fail 0.0.0.0:%d", port)
		return false
	}
	_ = l.Close()

	addr = "127.0.0.1:"
	l, err = net.Listen("tcp", addr+strconv.Itoa(port))
	if err != nil {
		log.Warnln("check port fail 127.0.0.1:%d", port)
		return false
	}
	_ = l.Close()
	log.Infoln("check port %d success", port)
	return true
}

func getFreePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

//export initClashCore
func initClashCore() {
	configHome := filepath.Join(os.Getenv("HOME"), ".config", "clash")
	constant.SetHomeDir(configHome)
	configFile := filepath.Join(configHome, "config.yaml")
	constant.SetConfig(configFile)
}

func readConfig(path string) ([]byte, error) {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, fmt.Errorf("Configuration file %s is empty", path)
	}
	return data, err
}

func getRawCfg() (*config.RawConfig, error) {
	buf, err := readConfig(constant.Path.Config())
	if err != nil {
		return nil, err
	}

	return config.UnmarshalRawConfig(buf)
}

func applySmartLightGBMOverrides(rawCfg *config.RawConfig) {
	if !smartLightGBMOverride {
		return
	}
	rawCfg.LgbmUrl = smartLightGBMURL
	rawCfg.LgbmAutoUpdate = smartLightGBMAutoUpdate
	if smartLightGBMUpdateInterval <= 0 {
		rawCfg.LgbmUpdateInterval = 72
	} else {
		rawCfg.LgbmUpdateInterval = smartLightGBMUpdateInterval
	}
}

func parseDefaultConfigThenStart(checkPort, allowLan, ipv6 bool, proxyPort uint32, externalController string) (*config.Config, error) {
	rawCfg, err := getRawCfg()
	if err != nil {
		return nil, err
	}

	if proxyPort > 0 {
		rawCfg.MixedPort = int(proxyPort)
		if rawCfg.Port == rawCfg.MixedPort {
			rawCfg.Port = 0
		}
		if rawCfg.SocksPort == rawCfg.MixedPort {
			rawCfg.SocksPort = 0
		}
	} else {
		if rawCfg.MixedPort == 0 {
			if rawCfg.Port > 0 {
				rawCfg.MixedPort = rawCfg.Port
				rawCfg.Port = 0
			} else if rawCfg.SocksPort > 0 {
				rawCfg.MixedPort = rawCfg.SocksPort
				rawCfg.SocksPort = 0
			} else {
				rawCfg.MixedPort = 7890
			}

			if rawCfg.SocksPort == rawCfg.MixedPort {
				rawCfg.SocksPort = 0
			}

			if rawCfg.Port == rawCfg.MixedPort {
				rawCfg.Port = 0
			}
		}
	}
	if secretOverride != "" {
		rawCfg.Secret = secretOverride
	}
	rawCfg.ExternalUI = ""
	rawCfg.Profile.StoreSelected = false
	enableIPV6 = ipv6
	rawCfg.IPv6 = ipv6
	if len(externalController) > 0 {
		rawCfg.ExternalController = externalController
	}
	if checkPort {
		if !isAddrValid(rawCfg.ExternalController) {
			port, err := getFreePort()
			if err != nil {
				return nil, err
			}
			rawCfg.ExternalController = "127.0.0.1:" + strconv.Itoa(port)
			rawCfg.Secret = ""
		}
		rawCfg.AllowLan = allowLan

		if !checkPortAvailable(rawCfg.MixedPort) {
			if port, err := getFreePort(); err == nil {
				rawCfg.MixedPort = port
			}
		}
	}
	applySmartLightGBMOverrides(rawCfg)

	cfg, err := config.ParseRawConfig(rawCfg)
	if err != nil {
		return nil, err
	}
	hub.ApplyConfig(cfg)
	if updater.GeoAutoUpdate() {
		updater.RegisterGeoUpdater()
	}
	if updater.LgbmAutoUpdate() {
		updater.RegisterLgbmUpdater()
	}
	return cfg, nil
}

//export verifyClashConfig
func verifyClashConfig(content *C.char) *C.char {

	b := []byte(C.GoString(content))
	cfg, err := executor.ParseWithBytes(b)
	if err != nil {
		return C.CString(err.Error())
	}

	if len(cfg.Proxies) < 1 {
		return C.CString("No proxy found in config")
	}
	return C.CString("success")
}

//export clashSetupLogger
func clashSetupLogger() {
	sub := log.Subscribe()
	go func() {
		for elm := range sub {
			cs := C.CString(elm.Payload)
			cl := C.CString(elm.Type())
			C.sendLogToUI(cs, cl)
			C.free(unsafe.Pointer(cs))
			C.free(unsafe.Pointer(cl))
		}
	}()
}

//export clashSetupTraffic
func clashSetupTraffic() {
	go func() {
		tick := time.NewTicker(time.Second)
		defer tick.Stop()
		t := statistic.DefaultManager
		buf := &bytes.Buffer{}
		for range tick.C {
			buf.Reset()
			up, down := t.Now()
			C.sendTrafficToUI(C.longlong(up), C.longlong(down))
		}
	}()
}

//export clash_checkSecret
func clash_checkSecret() *C.char {
	cfg, err := getRawCfg()
	if err != nil {
		return C.CString("")
	}
	if cfg.Secret != "" {
		return C.CString(cfg.Secret)
	}
	return C.CString("")
}

//export clash_setSecret
func clash_setSecret(secret *C.char) {
	secretOverride = C.GoString(secret)
}

//export clash_setLightGBMOptions
func clash_setLightGBMOptions(enableOverride bool, url *C.char, autoUpdate bool, updateInterval int) {
	smartLightGBMOverride = enableOverride
	smartLightGBMURL = C.GoString(url)
	smartLightGBMAutoUpdate = autoUpdate
	if updateInterval <= 0 {
		updateInterval = 72
	}
	smartLightGBMUpdateInterval = updateInterval
}

//export run
func run(checkConfig, allowLan, ipv6 bool, portOverride uint32, externalController *C.char) *C.char {
	cfg, err := parseDefaultConfigThenStart(checkConfig, allowLan, ipv6, portOverride, C.GoString(externalController))
	if err != nil {
		return C.CString(err.Error())
	}

	portInfo := map[string]string{
		"externalController": cfg.Controller.ExternalController,
		"secret":             cfg.Controller.Secret,
	}

	jsonString, err := json.Marshal(portInfo)
	if err != nil {
		return C.CString(err.Error())
	}

	return C.CString(string(jsonString))
}

//export setUIPath
func setUIPath(path *C.char) {
	route.SetUIPath(C.GoString(path))
}

//export clashUpdateConfig
func clashUpdateConfig(path *C.char) *C.char {
	buf, err := readConfig(C.GoString(path))
	if err != nil {
		return C.CString(err.Error())
	}
	rawCfg, err := config.UnmarshalRawConfig(buf)
	if err != nil {
		return C.CString(err.Error())
	}
	applySmartLightGBMOverrides(rawCfg)
	cfg, err := config.ParseRawConfig(rawCfg)
	if err != nil {
		return C.CString(err.Error())
	}
	cfg.General.IPv6 = enableIPV6
	cfg.Profile.StoreSelected = false
	executor.ApplyConfig(cfg, false)
	return C.CString("success")
}

//export clashGetConfigs
func clashGetConfigs() *C.char {
	general := executor.GetGeneral()
	jsonString, err := json.Marshal(general)
	if err != nil {
		return C.CString(err.Error())
	}
	return C.CString(string(jsonString))
}

//export verifyGEOIPDataBase
func verifyGEOIPDataBase() bool {
	if !mmdb.Verify(constant.Path.MMDB()) {
		log.Warnln("mmdb verify fail:%s", constant.Path.MMDB())
		return false
	}
	return true
}

//export clash_getCountryForIp
func clash_getCountryForIp(ip *C.char) *C.char {
	code := mmdb.IPInstance().LookupCode(net.ParseIP(C.GoString(ip)))
	if len(code) > 0 {
		return C.CString(strings.ToUpper(code[0]))
	}
	return C.CString("")
}

//export clash_closeAllConnections
func clash_closeAllConnections() {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
}

//export clash_getProggressInfo
func clash_getProggressInfo() *C.char {
	return C.CString(GetTcpNetList() + GetUDpList())
}

func main() {
}
