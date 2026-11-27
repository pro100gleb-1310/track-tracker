// Expo app: a full-screen WebView with the same page as Telegram and Android.
// Records live in the phone (AsyncStorage); the page keeps using localStorage, mirrored here by a small bridge.
import { useEffect, useState } from "react";
import { Linking, StyleSheet, useColorScheme, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { WebView } from "react-native-webview";
import AsyncStorage from "@react-native-async-storage/async-storage";
import html from "./html";

const BASE = "https://pro100gleb-1310.github.io/track-tracker/";
const KEY = "putevoy-storage"; // one JSON object { localStorageKey: value }; do not rename or records disappear

function bridge(saved) {
  return `(function(){
  var saved=${JSON.stringify(saved)}, has=function(k){return Object.prototype.hasOwnProperty.call(saved,k)};
  var post=function(k,v){try{window.ReactNativeWebView.postMessage(JSON.stringify(v===null?{k:k}:{k:k,v:v}))}catch(e){}};
  var ok=true;try{window.localStorage.length}catch(e){ok=false}
  if(!ok){
    var mem={getItem:function(k){return has(k)?saved[k]:null},
             setItem:function(k,v){saved[k]=String(v);post(k,String(v))},
             removeItem:function(k){delete saved[k];post(k,null)},
             clear:function(){Object.keys(saved).forEach(function(k){mem.removeItem(k)})},
             key:function(i){return Object.keys(saved)[i]||null}};
    Object.defineProperty(mem,"length",{get:function(){return Object.keys(saved).length}});
    try{Object.defineProperty(window,"localStorage",{value:mem,configurable:true})}catch(e){}
    return;
  }
  var p=Storage.prototype,oset=p.setItem,oget=p.getItem,orem=p.removeItem;
  p.setItem=function(k,v){v=String(v);if(this===window.localStorage){saved[k]=v;post(k,v)}try{oset.call(this,k,v)}catch(e){}};
  p.getItem=function(k){if(this===window.localStorage&&has(k))return saved[k];try{return oget.call(this,k)}catch(e){return null}};
  p.removeItem=function(k){if(this===window.localStorage){delete saved[k];post(k,null)}try{orem.call(this,k)}catch(e){}};
})();true;`;
}

let store = {};
let writing = Promise.resolve();
function save() {
  const json = JSON.stringify(store);
  writing = writing.then(() => AsyncStorage.setItem(KEY, json)).catch(() => {});
}

export default function App() {
  const [ready, setReady] = useState(false);
  const dark = useColorScheme() === "dark";
  const bg = dark ? "#15191c" : "#f3f4f1";

  useEffect(() => {
    AsyncStorage.getItem(KEY)
      .then((s) => { try { store = JSON.parse(s || "{}") || {}; } catch (e) { store = {}; } })
      .catch(() => {})
      .finally(() => setReady(true));
  }, []);

  const onMessage = (e) => {
    let m;
    try { m = JSON.parse(e.nativeEvent.data); } catch (_) { return; }
    if (!m || typeof m.k !== "string") return;
    if (typeof m.v === "string") store[m.k] = m.v; else delete store[m.k];
    save();
  };

  // Links to other sites open in the browser instead of replacing the app.
  const onShouldStart = (req) => {
    const u = req.url || "";
    if (u.startsWith(BASE) || u.startsWith("about:") || u.startsWith("data:") || u.startsWith("blob:")) return true;
    if (req.isTopFrame === false) return true;
    Linking.openURL(u).catch(() => {});
    return false;
  };

  return (
    <View style={[styles.root, { backgroundColor: bg }]}>
      <StatusBar style={dark ? "light" : "dark"} />
      {ready && (
        <WebView
          source={{ html, baseUrl: BASE }}
          originWhitelist={["*"]}
          injectedJavaScriptBeforeContentLoaded={bridge(store)}
          onMessage={onMessage}
          onShouldStartLoadWithRequest={onShouldStart}
          applicationNameForUserAgent="PutevoyUchet/iOS"
          contentInsetAdjustmentBehavior="never"
          automaticallyAdjustContentInsets={false}
          bounces={false}
          domStorageEnabled
          javaScriptEnabled
          setSupportMultipleWindows={false}
          style={{ flex: 1, backgroundColor: bg }}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({ root: { flex: 1 } });
