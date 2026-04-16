# Mesa Turnip for Adreno 8XX (main branch)

A modified build of Mesa Turnip with improved support for **Adreno 8XX**

The goal of this project is to improve stability and compatibility of Turnip on Adreno 8XX,  
where standard freedreno does not yet provide full functionality.

---

## 🔥 About the Project

This repository is based on:
- https://github.com/whitebelyash/mesa-tu8  
- https://github.com/whitebelyash/freedreno_turnip-Cl  

The **whitebelyash/gen8** branch already contains basic Adreno 8XX support.  
We task is to improve stability, fix rendering issues, and adapt the driver for real devices.

This is an **unofficial fork** created by an enthusiast.  
The code may contain experimental changes.

---

## ⚠️ Status

**Active development.**

- Bugs may occur  
- FPS drops may occur  
- Artifacts may occur  
- Issues with specific games may occur  
- Nothing is guaranteed  

This is just an attempt (possibly unsuccessful 🙂) 

---

## ✔ Supported GPUs

| GPU | Status |
|-----|--------|
| Adreno 810 | supported |
| Adreno 830 | supported |
| Adreno 840 | supported |
| Adreno 829 / 825 | supported |

---

## ✔ Testing is carried out on real devices

**Ludashi** Winlator was used, as the official Winlator may fail to run games.

---

## ❗ Important

If you experience:
- 0 FPS  
- game does not launch  
- Winlator shows 0 Vulkan Extensions  
- black screen  
- crash on startup  

This is **not necessarily a driver issue**.

Most often the culprit is:
- official Winlator  
- incorrect DXVK  
- broken container  
- incorrect Wine settings  

---

## 📝 If something isn't working

Please attach a log:

1. In Winlator, enable **Enable Wine Debug**  
2. Launch the game  
3. After the crash, open:  
   `Sdcard/winlator/logs`  
4. Attach the latest `.log` file

Without a log, it's impossible to determine the cause.

---

## 📌 Note

This project is created by an enthusiast and is not affiliated with Mesa, Qualcomm, or Winlator.  
Do not file bug reports in official Mesa repositories — this is an unofficial build.

---

source code location:
https://github.com/DiskDVD/mesa-tu8

---


## ❤️ Acknowledgments

Huge thanks to: https://t.me/hardwareunion

1) DeriSpace developer/tester
2) Lebron Project Manager 
3) Михаил Assistant
4) Ivan Romashin developer/tester

#THANKS TESTER!
1) Ikov5I (A829)
2) Whitedevil2427 (A829)
3) TXT (A830)
4) DeriSpace (A829)
5) Frane  (A810)
6) Ivan Romashin (A825)
7) My (A810)


- whitebelyash — for the TU8 base and gen8 support  
- Freedreno/Mesa team — for the open-source driver  
- Adreno 8XX community — for testing and feedback  

