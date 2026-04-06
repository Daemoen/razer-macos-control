# RazerControl - Open Source macOS App para Dispositivos Razer (Intel + Silicon)

## Context

O Razer Synapse para Mac requer Apple Silicon, deixando usuarios de Mac Intel sem acesso a configuracao de teclas macro, RGB e botoes extras. Este app resolve isso usando IOKit HID Manager (sem root, sem kext) baseado no protocolo USB documentado pelo OpenRazer (~280+ dispositivos). O usuario tem um BlackWidow V4 Pro e Pro Click V2 Vertical Edition.

## Dependencias Externas

**Nenhuma.** Tudo usa frameworks nativos do macOS:
- `IOKit` — USB HID communication
- `SwiftUI` / `AppKit` — GUI
- `CoreGraphics` — CGEventPost para synthetic key events
- `ApplicationServices` — Accessibility APIs

## Open Source Setup (Fase 0)

**Arquivos de projeto:**
- `README.md` — Descricao, screenshots placeholder, install instructions, supported devices, build from source
- `LICENSE` — GPLv2 (mesma licenca do OpenRazer, compativel pois usamos seu device database)
- `CONTRIBUTING.md` — How to add new devices, code style, PR process, testing guidelines
- `CLAUDE.md` — Instrucoes para AI assistants trabalhando no projeto
- `.gitignore` — Swift/Xcode/macOS ignores (.build/, .swiftpm/, DerivedData/, .DS_Store, *.xcuserdata)
- `CHANGELOG.md` — Keep a changelog format
- `.github/ISSUE_TEMPLATE/` — Bug report + device request templates
- `.github/PULL_REQUEST_TEMPLATE.md` — PR checklist

## Arquitetura

```
RazerControl.app (SwiftUI, dark theme)
├── Core/
│   ├── HID/          → IOKit HID Manager (device discovery, USB packets)
│   ├── Protocol/     → Razer USB protocol (90-byte packets, CRC, effects)
│   └── DeviceDB/     → Database estatico de ~280 PIDs + capabilities
├── Features/
│   ├── KeyMapping/   → Captura HID input → remap → CGEventPost
│   ├── RGB/          → Controle de efeitos (static, wave, breathing, spectrum, per-key)
│   └── Profiles/     → Save/load perfis por dispositivo (JSON em ~/Library/Application Support/)
├── UI/
│   ├── MainWindow    → Device selector + tab navigation
│   ├── KeyboardTab   → Visual keyboard layout + key mapper + test input field
│   ├── MouseTab      → Visual mouse layout + button mapper
│   ├── LightingTab   → Color picker + effect selector + live preview
│   └── SetupWizard   → Permission requests (Input Monitoring, Accessibility)
└── Installer/
    └── DMG + setup script for permissions
```

## Stack Tecnica

- **Linguagem:** Swift 6.2 / SwiftUI (macOS 13+, Intel e Silicon)
- **USB:** IOKit HID Manager (`IOHIDDeviceSetReport` / `IOHIDDeviceGetReport`)
- **Input capture:** IOKit HID value callbacks (requer Input Monitoring TCC)
- **Synthetic events:** CGEventPost (requer Accessibility TCC)
- **Build:** Swift Package Manager (SPM) com target executavel
- **Distribuicao:** DMG com app bundle ad-hoc signed

## Fases de Implementacao

### Fase 1: Projeto base + HID Core
**Arquivos:**
- `Package.swift` — SPM config com dependencias (nenhuma externa necessaria)
- `Sources/RazerControl/App/RazerControlApp.swift` — @main entry, WindowGroup, dark theme
- `Sources/RazerControl/App/AppDelegate.swift` — NSApplicationDelegate, menu bar icon
- `Sources/RazerControl/Core/HID/HIDManager.swift` — IOKit device discovery, hotplug monitoring
- `Sources/RazerControl/Core/HID/HIDDevice.swift` — Open/close device, send/receive reports
- `Sources/RazerControl/Core/Protocol/RazerPacket.swift` — 90-byte packet struct, CRC calc, command builders
- `Sources/RazerControl/Core/Protocol/RazerCommands.swift` — Static/wave/breathing/spectrum/per-key commands
- `Sources/RazerControl/Core/Protocol/RazerConstants.swift` — LED IDs, effect IDs, transaction IDs, timing

### Fase 2: Device Database
**Arquivos:**
- `Sources/RazerControl/Core/DeviceDB/DeviceDatabase.swift` — Lookup PID → DeviceInfo
- `Sources/RazerControl/Core/DeviceDB/DeviceInfo.swift` — Struct: name, type, PID, capabilities, matrix dims, zones, protocol version
- `Sources/RazerControl/Core/DeviceDB/Keyboards.swift` — ~120 keyboard definitions
- `Sources/RazerControl/Core/DeviceDB/Mice.swift` — ~130 mouse definitions
- `Sources/RazerControl/Core/DeviceDB/Accessories.swift` — ~28 accessory definitions

Cada device tem:
```swift
DeviceInfo(
    pid: 0x028D,
    name: "BlackWidow V4 Pro",
    type: .keyboard,
    features: [.macroKeys, .matrixRGB, .dial],
    matrixDims: (6, 22),
    zones: [.backlight, .logo],
    protocol: .extended,
    transactionId: 0x1F,
    hasMacroKeys: true,
    macroKeyCount: 5
)
```

### Fase 3: UI — Main Window + Device Selector
**Arquivos:**
- `Sources/RazerControl/UI/Theme/RazerTheme.swift` — Dark theme colors (Razer green #00FF00, dark grays), typography, spacing
- `Sources/RazerControl/UI/Components/DeviceSelector.swift` — Dropdown com devices conectados, icone por tipo
- `Sources/RazerControl/UI/MainView.swift` — TabView com Keyboard, Mouse, Lighting tabs
- `Sources/RazerControl/UI/Components/StatusBar.swift` — Connection status, battery (se wireless)

### Fase 4: Keyboard Tab — Visual Layout + Key Mapping
**Arquivos:**
- `Sources/RazerControl/UI/Keyboard/KeyboardView.swift` — Container view
- `Sources/RazerControl/UI/Keyboard/KeyboardLayoutView.swift` — Visual keyboard render (Canvas/Path), highlight key on hover/click
- `Sources/RazerControl/UI/Keyboard/KeyMapperSheet.swift` — Sheet para configurar mapping de uma tecla: source key → target action
- `Sources/RazerControl/UI/Keyboard/TestInputView.swift` — TextField para testar remaps em tempo real
- `Sources/RazerControl/UI/Keyboard/MacroKeyPanel.swift` — Panel lateral para M1-M5 com status (ativo/inativo) e init button
- `Sources/RazerControl/Features/KeyMapping/KeyMapper.swift` — Engine: IOKit HID callback → intercept → remap → CGEventPost
- `Sources/RazerControl/Features/KeyMapping/KeyProfile.swift` — Codable struct para salvar/carregar perfis
- `Sources/RazerControl/Features/KeyMapping/KeyCodes.swift` — Mapa HID keycode → nome legivel + macOS virtual keycode

**Key mapping flow:**
1. User clica tecla no visual keyboard → abre KeyMapperSheet
2. Seleciona acao: keystroke, shortcut, app launch, media control, ou macro sequence
3. Salva no perfil → KeyMapper atualiza callback
4. User testa no TestInputView

### Fase 5: Mouse Tab — Visual Layout + Button Mapping
**Arquivos:**
- `Sources/RazerControl/UI/Mouse/MouseView.swift` — Container view
- `Sources/RazerControl/UI/Mouse/MouseLayoutView.swift` — Visual mouse render com botoes clicaveis
- `Sources/RazerControl/UI/Mouse/ButtonMapperSheet.swift` — Configurar acao de cada botao
- `Sources/RazerControl/UI/Mouse/DPIView.swift` — Slider/stages para DPI (se suportado)
- `Sources/RazerControl/Features/KeyMapping/MouseMapper.swift` — Similar ao KeyMapper mas para mouse buttons

### Fase 6: Lighting Tab — RGB Control
**Arquivos:**
- `Sources/RazerControl/UI/Lighting/LightingView.swift` — Container com zone selector + effect picker
- `Sources/RazerControl/UI/Lighting/ColorPickerView.swift` — Color wheel + RGB sliders + hex input + presets
- `Sources/RazerControl/UI/Lighting/EffectSelector.swift` — Grid de efeitos: Static, Breathing, Wave, Spectrum, Reactive, Starlight
- `Sources/RazerControl/UI/Lighting/EffectPreview.swift` — Canvas animado mostrando preview do efeito
- `Sources/RazerControl/UI/Lighting/PerKeyEditor.swift` — Editor per-key RGB (se device suporta matrix)
- `Sources/RazerControl/Features/RGB/RGBController.swift` — Traduz UI selections → RazerCommands → envia via HID

### Fase 7: Setup Wizard + Permissions
**Arquivos:**
- `Sources/RazerControl/UI/Setup/SetupWizardView.swift` — Onboarding em steps
- `Sources/RazerControl/UI/Setup/PermissionCheckView.swift` — Verifica e solicita Input Monitoring + Accessibility
- `Sources/RazerControl/Core/Permissions/PermissionManager.swift` — Check TCC status via IOKit/AX APIs, open System Settings deeplinks

**Flow:**
1. Primeiro launch → SetupWizard
2. Step 1: "Detectando dispositivos..." (scan HID)
3. Step 2: "Permissoes necessarias" → explica por que + botao para abrir System Settings
4. Step 3: "Pronto!" → vai para MainView

### Fase 8: Profiles + Persistence
**Arquivos:**
- `Sources/RazerControl/Features/Profiles/ProfileManager.swift` — CRUD de perfis em ~/Library/Application Support/RazerControl/
- `Sources/RazerControl/Features/Profiles/Profile.swift` — Codable: key mappings + lighting config + DPI por device

### Fase 9: Installer + Distribution
- `Scripts/create-dmg.sh` — Cria DMG com app bundle
- `Scripts/sign.sh` — Ad-hoc code signing
- `Info.plist` — Bundle config, LSUIElement, required device capabilities
- `Resources/Assets.xcassets/` — App icon, device images

## Protocolo USB Razer (referencia rapida)

```
Packet: 90 bytes total
[0]     status (0x00 = new)
[1]     transaction_id (varies per device: 0xFF, 0x3F, 0x1F, 0x9F)
[2-3]   remaining_packets (0x0000)
[4]     protocol_type (0x00)
[5]     data_size (payload length)
[6]     command_class
[7]     command_id
[8-87]  arguments (80 bytes max)
[88]    crc (XOR bytes 2..87)
[89]    reserved (0x00)

USB Control Transfer: requestType=0x21, request=0x09, value=0x300, index=0x02
```

**Comandos chave:**
| Funcao | Class | ID | Args |
|--------|-------|----|------|
| Init macro keys | 0x00 | 0x04 | [0x03, 0x00] |
| Static color (std) | 0x03 | 0x0A | [0x06, R, G, B] |
| Wave (std) | 0x03 | 0x0A | [0x01, dir] |
| Breathing (std) | 0x03 | 0x0A | [0x03, 0x01, R, G, B, 0, 0, 0] |
| Spectrum (std) | 0x03 | 0x0A | [0x04] |
| Static (ext) | 0x0F | 0x02 | [storage, led, 0x01, 0, 0, 1, R, G, B] |

## Permissoes Necessarias

| Permissao | Para que | Quando |
|-----------|----------|--------|
| Input Monitoring | Ler teclas macro, capturar key events para remapping | Key mapping feature |
| Accessibility | Injetar teclas sinteticas via CGEventPost | Key mapping feature |
| Nenhuma | RGB lighting, device detection, init macro keys | Lighting feature |

## Verificacao / Testes

1. **Build:** `swift build` no diretorio do projeto
2. **Run:** `swift run RazerControl` ou abrir o .app bundle
3. **Device detection:** Conectar qualquer device Razer USB → deve aparecer no DeviceSelector
4. **RGB test:** Selecionar device → Lighting tab → escolher cor → device deve mudar
5. **Macro init:** Keyboard tab → clicar "Initialize Macro Keys" → M1-M5 devem comecar a emitir F13-F17
6. **Key mapping:** Mapear M1→Cmd+C → testar no TestInputView
7. **Mouse buttons:** Mouse tab → remapear Button 4 → testar

## Trade-offs e Decisoes

1. **Database estatica vs dinamica:** Estatica (hardcoded por PID) porque nao ha query protocol no USB. Requer update do app para novos devices — contributors podem adicionar facilmente.
2. **IOKit vs libusb:** IOKit — sem root no macOS, funciona ao lado do kernel driver.
3. **SwiftUI vs AppKit:** SwiftUI com AppKit bridges onde necessario (NSEvent monitoring, CGEvent).
4. **SPM vs Xcode project:** SPM — mais limpo para gerar via CLI, sem .xcodeproj files complexos. Usamos xcodebuild para gerar o .app bundle.
5. **Licenca GPLv2:** Compativel com OpenRazer (de onde vem a device database e protocol docs). Permite uso comercial mas exige source disclosure.

## Ordem de Implementacao

1. **Fase 0** — Open source scaffolding (git, README, LICENSE, CONTRIBUTING, CLAUDE.md, .gitignore)
2. **Fase 1** — SPM project + HID Core (device discovery + USB packet protocol)
3. **Fase 2** — Device Database (PIDs + capabilities from OpenRazer)
4. **Fase 3** — UI shell (dark theme, device selector, tab navigation)
5. **Fase 4** — Lighting tab (RGB control — funciona SEM permissoes, melhor para testar primeiro)
6. **Fase 5** — Keyboard tab (visual layout, macro key init, key mapping, test input)
7. **Fase 6** — Mouse tab (visual layout, button mapping, DPI)
8. **Fase 7** — Setup wizard + permission management
9. **Fase 8** — Profiles + persistence
10. **Fase 9** — Installer (DMG + signing)
