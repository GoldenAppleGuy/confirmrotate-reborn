#!/usr/bin/env python3
# Writes the translations into prefs/Resources/<language>.lproj:
#   Root.strings  - the settings page (Root.plist labels, footers and titles, plus text set in code)
#   Tweak.strings - the button (read by the tweak from the settings bundle)
# Keys are the English text. Run after changing any user-visible string; it fails if a string in
# Root.plist has no translation. Output is XML property lists, which iOS reads as .strings files.
import os, plistlib, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, '..', 'Resources')

F_APPS = 'Whitelisted apps are the only ones the tweak acts in. Blacklisted apps rotate freely, as without the tweak. Always Show In is for apps that handle rotation themselves.'
F_BEHAVIOR = 'Auto-Rotate rotates after a delay while a ring fills around the button, in place of Hide After; with Tap to Cancel, a tap keeps the screen as it is. Long press the button to rotate and blacklist the app; swipe it to dismiss.'
F_APPEARANCE = 'Position is the distance from the status bar, along the side of the screen.'

# Settings page. Order of each row: de, es, fr, it, ja, ko, nl, pt-BR, ru, zh-Hans, zh-Hant, tr, pl
LANGUAGES = ['de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant', 'tr', 'pl']
ROOT = {
    'Enabled': ['Aktiviert', 'Activado', 'Activé', 'Attivo', '有効', '활성화', 'Ingeschakeld', 'Ativado', 'Включено', '启用', '啟用', 'Etkin', 'Włączone'],
    'Apps': ['Apps', 'Apps', 'Apps', 'App', 'App', '앱', 'Apps', 'Apps', 'Приложения', 'App', 'App', 'Uygulamalar', 'Aplikacje'],
    'Whitelisted Apps': ['Apps auf der Whitelist', 'Apps en la lista blanca', 'Apps en liste blanche', 'App nella whitelist', 'ホワイトリストのApp', '화이트리스트 앱', 'Apps op de whitelist', 'Apps na lista branca', 'Белый список', '白名单 App', '白名單 App', 'Beyaz Listedeki Uygulamalar', 'Aplikacje na białej liście'],
    'Blacklisted Apps': ['Apps auf der Blacklist', 'Apps en la lista negra', 'Apps en liste noire', 'App nella blacklist', 'ブラックリストのApp', '블랙리스트 앱', 'Apps op de blacklist', 'Apps na lista negra', 'Чёрный список', '黑名单 App', '黑名單 App', 'Kara Listedeki Uygulamalar', 'Aplikacje na czarnej liście'],
    'Always Show In': ['Immer anzeigen in', 'Mostrar siempre en', 'Toujours afficher dans', 'Mostra sempre in', '常に表示するApp', '항상 표시할 앱', 'Altijd tonen in', 'Sempre mostrar em', 'Всегда показывать в', '始终显示于', '永遠顯示於', 'Her Zaman Göster', 'Zawsze pokazuj w'],
    F_APPS: [
        'Nur in Apps auf der Whitelist ist der Tweak aktiv. Apps auf der Blacklist drehen sich frei, wie ohne den Tweak. „Immer anzeigen in“ ist für Apps gedacht, die die Drehung selbst steuern.',
        'Las apps de la lista blanca son las únicas en las que actúa el tweak. Las apps de la lista negra giran libremente, como sin el tweak. «Mostrar siempre en» es para apps que gestionan el giro por sí mismas.',
        'Le tweak n’agit que dans les apps de la liste blanche. Les apps de la liste noire pivotent librement, comme sans le tweak. « Toujours afficher dans » sert aux apps qui gèrent elles-mêmes la rotation.',
        'Il tweak agisce solo nelle app della whitelist. Le app della blacklist ruotano liberamente, come senza il tweak. «Mostra sempre in» è per le app che gestiscono da sole la rotazione.',
        'ホワイトリストのAppでのみ動作します。ブラックリストのAppは、このTweakがない時と同じように自由に回転します。「常に表示するApp」は回転を自分で処理するApp向けです。',
        '화이트리스트에 있는 앱에서만 트윅이 작동합니다. 블랙리스트에 있는 앱은 트윅이 없는 것처럼 자유롭게 회전합니다. ‘항상 표시할 앱’은 회전을 직접 처리하는 앱을 위한 것입니다.',
        'De tweak werkt alleen in apps op de whitelist. Apps op de blacklist draaien vrij, zoals zonder de tweak. ‘Altijd tonen in’ is voor apps die het draaien zelf regelen.',
        'O tweak só atua nos apps da lista branca. Os apps da lista negra giram livremente, como sem o tweak. “Sempre mostrar em” é para apps que controlam a rotação sozinhos.',
        'Твик работает только в приложениях из белого списка. Приложения из чёрного списка поворачиваются свободно, как без твика. «Всегда показывать в» — для приложений, которые сами управляют поворотом.',
        '插件仅在白名单 App 中生效。黑名单 App 可自由旋转，如同未安装插件。“始终显示于”适用于自行处理旋转的 App。',
        '插件只在白名單 App 中生效。黑名單 App 可自由旋轉，如同未安裝插件。「永遠顯示於」適用於自行處理旋轉的 App。',
        'Tweak yalnızca beyaz listedeki uygulamalarda çalışır. Kara listedeki uygulamalar, tweak yokmuş gibi serbestçe döner. “Her Zaman Göster”, dönüşü kendisi yöneten uygulamalar içindir.',
        'Tweak działa tylko w aplikacjach z białej listy. Aplikacje z czarnej listy obracają się swobodnie, jak bez tweaka. „Zawsze pokazuj w” jest dla aplikacji, które same obsługują obracanie.',
    ],
    'Behavior': ['Verhalten', 'Comportamiento', 'Comportement', 'Comportamento', '動作', '동작', 'Gedrag', 'Comportamento', 'Поведение', '行为', '行為', 'Davranış', 'Działanie'],
    'Portrait on App Switch': ['Hochformat beim App-Wechsel', 'Vertical al cambiar de app', 'Portrait au changement d’app', 'Verticale al cambio di app', 'App切り替え時に縦向き', '앱 전환 시 세로 모드', 'Staand bij wisselen van app', 'Retrato ao trocar de app', 'Портрет при смене приложения', '切换 App 时竖屏', '切換 App 時直向', 'Uygulama Değişince Dikey', 'Pion przy zmianie aplikacji'],
    'Auto-Rotate': ['Automatisch drehen', 'Girar automáticamente', 'Rotation automatique', 'Rotazione automatica', '自動回転', '자동 회전', 'Automatisch draaien', 'Girar automaticamente', 'Автоповорот', '自动旋转', '自動旋轉', 'Otomatik Döndür', 'Automatyczny obrót'],
    'Tap to Cancel': ['Tippen zum Abbrechen', 'Tocar para cancelar', 'Toucher pour annuler', 'Tocca per annullare', 'タップでキャンセル', '탭하여 취소', 'Tik om te annuleren', 'Toque para cancelar', 'Нажатие отменяет', '轻点取消', '點一下取消', 'Dokunarak İptal', 'Stuknij, aby anulować'],
    'Delay': ['Verzögerung', 'Retraso', 'Délai', 'Ritardo', '待ち時間', '지연 시간', 'Vertraging', 'Atraso', 'Задержка', '延迟', '延遲', 'Gecikme', 'Opóźnienie'],
    'Show After': ['Einblenden nach', 'Mostrar tras', 'Afficher après', 'Mostra dopo', '表示まで', '표시까지', 'Tonen na', 'Mostrar após', 'Показывать через', '显示时间', '顯示時間', 'Gösterme Süresi', 'Pokaż po'],
    'Hide After': ['Ausblenden nach', 'Ocultar tras', 'Masquer après', 'Nascondi dopo', '非表示まで', '숨기기까지', 'Verbergen na', 'Ocultar após', 'Скрывать через', '隐藏时间', '隱藏時間', 'Gizleme Süresi', 'Ukryj po'],
    'Haptic Feedback': ['Haptisches Feedback', 'Respuesta háptica', 'Retour haptique', 'Feedback aptico', '触覚フィードバック', '햅틱 피드백', 'Haptische feedback', 'Resposta tátil', 'Тактильный отклик', '触感反馈', '觸覺回饋', 'Dokunsal Geri Bildirim', 'Wibracje'],
    F_BEHAVIOR: [
        '„Automatisch drehen“ dreht nach einer Verzögerung, während sich ein Ring um die Taste füllt, anstelle von „Ausblenden nach“. Mit „Tippen zum Abbrechen“ bleibt der Bildschirm bei einem Tippen, wie er ist. Lange auf die Taste drücken, um zu drehen und die App auf die Blacklist zu setzen; wischen, um sie auszublenden.',
        '«Girar automáticamente» gira tras un retraso mientras un anillo se llena alrededor del botón, en lugar de «Ocultar tras». Con «Tocar para cancelar», un toque deja la pantalla como está. Mantén pulsado el botón para girar y añadir la app a la lista negra; deslízalo para descartarlo.',
        'La rotation automatique fait pivoter l’écran après un délai, pendant qu’un anneau se remplit autour du bouton, à la place de « Masquer après ». Avec « Toucher pour annuler », un toucher laisse l’écran tel quel. Maintenez le bouton pour pivoter et mettre l’app en liste noire ; balayez-le pour le masquer.',
        'La rotazione automatica ruota dopo un ritardo mentre un anello si riempie attorno al pulsante, al posto di «Nascondi dopo». Con «Tocca per annullare», un tocco lascia lo schermo com’è. Tieni premuto il pulsante per ruotare e aggiungere l’app alla blacklist; scorrilo per chiuderlo.',
        '自動回転は、ボタンの周りのリングが満ちると回転します（「非表示まで」の代わり）。「タップでキャンセル」がオンの場合、タップすると画面はそのままです。ボタンを長押しすると回転してAppをブラックリストに追加し、スワイプすると閉じます。',
        '자동 회전은 버튼 주위의 링이 채워지면 회전하며, ‘숨기기까지’ 대신 사용됩니다. ‘탭하여 취소’를 켜면 탭할 때 화면이 그대로 유지됩니다. 버튼을 길게 누르면 회전하고 앱을 블랙리스트에 추가하며, 쓸어 넘기면 닫힙니다.',
        '‘Automatisch draaien’ draait na een vertraging terwijl een ring zich rond de knop vult, in plaats van ‘Verbergen na’. Met ‘Tik om te annuleren’ blijft het scherm bij een tik zoals het is. Houd de knop ingedrukt om te draaien en de app op de blacklist te zetten; veeg hem weg om hem te sluiten.',
        '“Girar automaticamente” gira após um atraso enquanto um anel se completa ao redor do botão, no lugar de “Ocultar após”. Com “Toque para cancelar”, um toque mantém a tela como está. Mantenha o botão pressionado para girar e adicionar o app à lista negra; deslize-o para dispensá-lo.',
        'Автоповорот поворачивает экран после задержки, пока вокруг кнопки заполняется кольцо, вместо «Скрывать через». С «Нажатие отменяет» нажатие оставляет экран как есть. Удерживайте кнопку, чтобы повернуть экран и добавить приложение в чёрный список; смахните её, чтобы скрыть.',
        '自动旋转会在按钮周围的圆环填满后旋转，代替“隐藏时间”。开启“轻点取消”后，轻点按钮会保持屏幕不变。长按按钮可旋转并将 App 加入黑名单；轻扫可将其关闭。',
        '自動旋轉會在按鈕周圍的圓環填滿後旋轉，取代「隱藏時間」。開啟「點一下取消」後，點一下按鈕會保持螢幕不變。按住按鈕可旋轉並將 App 加入黑名單；滑動可將其關閉。',
        'Otomatik Döndür, düğmenin çevresindeki halka dolunca ekranı döndürür ve “Gizleme Süresi”nin yerini alır. “Dokunarak İptal” açıkken dokunmak ekranı olduğu gibi bırakır. Döndürüp uygulamayı kara listeye eklemek için düğmeye uzun basın; kapatmak için kaydırın.',
        'Automatyczny obrót obraca ekran po opóźnieniu, gdy wokół przycisku zapełnia się pierścień, zamiast „Ukryj po”. Z opcją „Stuknij, aby anulować” stuknięcie pozostawia ekran bez zmian. Przytrzymaj przycisk, aby obrócić i dodać aplikację do czarnej listy; przesuń go, aby go zamknąć.',
    ],
    'Appearance': ['Darstellung', 'Apariencia', 'Apparence', 'Aspetto', '外観', '모양', 'Weergave', 'Aparência', 'Внешний вид', '外观', '外觀', 'Görünüm', 'Wygląd'],
    'Automatic': ['Automatisch', 'Automático', 'Automatique', 'Automatico', '自動', '자동', 'Automatisch', 'Automático', 'Автоматически', '自动', '自動', 'Otomatik', 'Automatycznie'],
    'Light': ['Hell', 'Claro', 'Clair', 'Chiaro', 'ライト', '라이트', 'Licht', 'Claro', 'Светлое', '浅色', '淺色', 'Açık', 'Jasny'],
    'Dark': ['Dunkel', 'Oscuro', 'Sombre', 'Scuro', 'ダーク', '다크', 'Donker', 'Escuro', 'Тёмное', '深色', '深色', 'Koyu', 'Ciemny'],
    'Background': ['Hintergrund', 'Fondo', 'Arrière-plan', 'Sfondo', '背景', '배경', 'Achtergrond', 'Fundo', 'Фон', '背景', '背景', 'Arka Plan', 'Tło'],
    'System Blur': ['Systemunschärfe', 'Desenfoque del sistema', 'Flou système', 'Sfocatura di sistema', 'システムのぼかし', '시스템 흐림', 'Systeemvervaging', 'Desfoque do sistema', 'Системное размытие', '系统模糊', '系統模糊', 'Sistem Bulanıklığı', 'Rozmycie systemowe'],
    'Custom': ['Eigene', 'Personalizado', 'Personnalisé', 'Personalizzato', 'カスタム', '사용자 지정', 'Aangepast', 'Personalizado', 'Своё', '自定', '自訂', 'Özel', 'Własny'],
    'Custom…': ['Eigene …', 'Personalizado…', 'Personnalisé…', 'Personalizzato…', 'カスタム…', '사용자 지정…', 'Aangepast…', 'Personalizado…', 'Своё…', '自定…', '自訂…', 'Özel…', 'Własny…'],
    'Circle': ['Kreis', 'Círculo', 'Cercle', 'Cerchio', '円', '원형', 'Cirkel', 'Círculo', 'Круг', '圆形', '圓形', 'Daire', 'Koło'],
    'Rounded Square': ['Abgerundetes Quadrat', 'Cuadrado redondeado', 'Carré arrondi', 'Quadrato arrotondato', '角丸四角形', '둥근 사각형', 'Afgerond vierkant', 'Quadrado arredondado', 'Скруглённый квадрат', '圆角方形', '圓角方形', 'Yuvarlatılmış Kare', 'Zaokrąglony kwadrat'],
    'Icon Color': ['Symbolfarbe', 'Color del icono', 'Couleur de l’icône', 'Colore icona', 'アイコンの色', '아이콘 색상', 'Symboolkleur', 'Cor do ícone', 'Цвет значка', '图标颜色', '圖像顏色', 'Simge Rengi', 'Kolor ikony'],
    'Default': ['Standard', 'Predeterminado', 'Par défaut', 'Predefinito', 'デフォルト', '기본', 'Standaard', 'Padrão', 'По умолчанию', '默认', '預設', 'Varsayılan', 'Domyślny'],
    'Blue': ['Blau', 'Azul', 'Bleu', 'Blu', '青', '파란색', 'Blauw', 'Azul', 'Синий', '蓝色', '藍色', 'Mavi', 'Niebieski'],
    'Green': ['Grün', 'Verde', 'Vert', 'Verde', '緑', '초록색', 'Groen', 'Verde', 'Зелёный', '绿色', '綠色', 'Yeşil', 'Zielony'],
    'Orange': ['Orange', 'Naranja', 'Orange', 'Arancione', 'オレンジ', '주황색', 'Oranje', 'Laranja', 'Оранжевый', '橙色', '橙色', 'Turuncu', 'Pomarańczowy'],
    'Pink': ['Pink', 'Rosa', 'Rose', 'Rosa', 'ピンク', '분홍색', 'Roze', 'Rosa', 'Розовый', '粉色', '粉紅色', 'Pembe', 'Różowy'],
    'Purple': ['Lila', 'Morado', 'Violet', 'Viola', '紫', '보라색', 'Paars', 'Roxo', 'Фиолетовый', '紫色', '紫色', 'Mor', 'Fioletowy'],
    'Red': ['Rot', 'Rojo', 'Rouge', 'Rosso', '赤', '빨간색', 'Rood', 'Vermelho', 'Красный', '红色', '紅色', 'Kırmızı', 'Czerwony'],
    'Teal': ['Türkis', 'Turquesa', 'Bleu canard', 'Verde acqua', 'ティール', '청록색', 'Groenblauw', 'Azul-petróleo', 'Бирюзовый', '青色', '藍綠色', 'Camgöbeği', 'Morski'],
    'Yellow': ['Gelb', 'Amarillo', 'Jaune', 'Giallo', '黄', '노란색', 'Geel', 'Amarelo', 'Жёлтый', '黄色', '黃色', 'Sarı', 'Żółty'],
    'Size': ['Größe', 'Tamaño', 'Taille', 'Dimensione', 'サイズ', '크기', 'Grootte', 'Tamanho', 'Размер', '大小', '大小', 'Boyut', 'Rozmiar'],
    'Opacity': ['Deckkraft', 'Opacidad', 'Opacité', 'Opacità', '不透明度', '불투명도', 'Dekking', 'Opacidade', 'Непрозрачность', '不透明度', '不透明度', 'Opaklık', 'Krycie'],
    'Position': ['Position', 'Posición', 'Position', 'Posizione', '位置', '위치', 'Positie', 'Posição', 'Положение', '位置', '位置', 'Konum', 'Położenie'],
    F_APPEARANCE: [
        'Die Position ist der Abstand zur Statusleiste entlang des Bildschirmrands.',
        'La posición es la distancia desde la barra de estado, a lo largo del lateral de la pantalla.',
        'La position est la distance depuis la barre d’état, le long du bord de l’écran.',
        'La posizione è la distanza dalla barra di stato, lungo il lato dello schermo.',
        '位置は、画面の側面に沿ったステータスバーからの距離です。',
        '위치는 화면 측면을 따라 상태 막대로부터의 거리입니다.',
        'De positie is de afstand tot de statusbalk, langs de zijkant van het scherm.',
        'A posição é a distância da barra de status, ao longo da lateral da tela.',
        'Положение — расстояние от строки состояния вдоль края экрана.',
        '位置是沿屏幕侧边与状态栏的距离。',
        '位置是沿螢幕側邊與狀態列的距離。',
        'Konum, ekranın kenarı boyunca durum çubuğuna olan uzaklıktır.',
        'Położenie to odległość od paska stanu wzdłuż boku ekranu.',
    ],
    # Diagnostics
    'Diagnostics': ['Diagnose', 'Diagnóstico', 'Diagnostic', 'Diagnostica', '診断', '진단', 'Diagnose', 'Diagnóstico', 'Диагностика', '诊断', '診斷', 'Tanılama', 'Diagnostyka'],
    'Share Log creates a report for bug reports: the log, settings, jailbreak, device and iOS version, and the latest SpringBoard crash report if there is one. Record Rotation Test adds what SpringBoard does while the phone is turned.': [
        '„Protokoll teilen“ erstellt einen Bericht für Fehlermeldungen: Protokoll, Einstellungen, Jailbreak, Gerät und iOS-Version sowie den neuesten SpringBoard-Absturzbericht, falls vorhanden. „Drehtest aufzeichnen“ ergänzt, was SpringBoard beim Drehen des iPhone tut.',
        '«Compartir registro» crea un informe para reportar errores: el registro, los ajustes, el jailbreak, el dispositivo y la versión de iOS, y el último informe de fallo de SpringBoard si lo hay. «Grabar prueba de giro» añade lo que hace SpringBoard al girar el teléfono.',
        '« Partager le journal » crée un rapport pour signaler un bug : le journal, les réglages, le jailbreak, l’appareil et la version d’iOS, et le dernier rapport de plantage de SpringBoard s’il y en a un. « Enregistrer un test de rotation » y ajoute ce que fait SpringBoard quand on tourne le téléphone.',
        '«Condividi registro» crea un rapporto per segnalare errori: il registro, le impostazioni, il jailbreak, il dispositivo e la versione di iOS, e l’ultimo rapporto di arresto di SpringBoard, se presente. «Registra test di rotazione» aggiunge ciò che fa SpringBoard mentre il telefono viene ruotato.',
        '「ログを共有」は不具合報告用のレポートを作成します（ログ、設定、脱獄環境、デバイスとiOSバージョン、あれば最新のSpringBoardクラッシュレポート）。「回転テストを記録」は、端末を回したときのSpringBoardの動作を追加します。',
        '‘로그 공유’는 버그 신고용 보고서를 만듭니다: 로그, 설정, 탈옥 환경, 기기 및 iOS 버전, 그리고 있는 경우 최신 SpringBoard 충돌 보고서. ‘회전 테스트 기록’은 기기를 돌릴 때 SpringBoard의 동작을 추가합니다.',
        '‘Log delen’ maakt een rapport voor foutmeldingen: het log, de instellingen, de jailbreak, het apparaat en de iOS-versie, en het nieuwste SpringBoard-crashrapport als dat er is. ‘Draaitest opnemen’ voegt toe wat SpringBoard doet terwijl de telefoon wordt gedraaid.',
        '“Compartilhar registro” cria um relatório para reportar erros: o registro, os ajustes, o jailbreak, o dispositivo e a versão do iOS, e o relatório de falha mais recente do SpringBoard, se houver. “Gravar teste de rotação” adiciona o que o SpringBoard faz enquanto o telefone é girado.',
        '«Поделиться журналом» создаёт отчёт для сообщений об ошибках: журнал, настройки, джейлбрейк, устройство и версию iOS, а также последний отчёт о сбое SpringBoard, если он есть. «Записать тест поворота» добавляет, что делает SpringBoard при повороте телефона.',
        '“共享日志”会生成用于报告问题的报告：日志、设置、越狱环境、设备和 iOS 版本，以及最新的 SpringBoard 崩溃报告（如有）。“录制旋转测试”会加入转动手机时 SpringBoard 的行为。',
        '「分享記錄」會產生用於回報問題的報告：記錄、設定、越獄環境、裝置與 iOS 版本，以及最新的 SpringBoard 當機報告（如有）。「錄製旋轉測試」會加入轉動手機時 SpringBoard 的行為。',
        '“Günlüğü Paylaş” hata bildirimi için bir rapor oluşturur: günlük, ayarlar, jailbreak, aygıt ve iOS sürümü ile varsa en son SpringBoard çökme raporu. “Döndürme Testini Kaydet”, telefon döndürülürken SpringBoard’un yaptıklarını ekler.',
        '„Udostępnij dziennik” tworzy raport do zgłaszania błędów: dziennik, ustawienia, jailbreak, urządzenie i wersję iOS oraz najnowszy raport awarii SpringBoard, jeśli istnieje. „Nagraj test obrotu” dodaje to, co robi SpringBoard podczas obracania telefonu.',
    ],
    'Record Rotation Test': ['Drehtest aufzeichnen', 'Grabar prueba de giro', 'Enregistrer un test de rotation', 'Registra test di rotazione', '回転テストを記録', '회전 테스트 기록', 'Draaitest opnemen', 'Gravar teste de rotação', 'Записать тест поворота', '录制旋转测试', '錄製旋轉測試', 'Döndürme Testini Kaydet', 'Nagraj test obrotu'],
    'Rotation Test': ['Drehtest', 'Prueba de giro', 'Test de rotation', 'Test di rotazione', '回転テスト', '회전 테스트', 'Draaitest', 'Teste de rotação', 'Тест поворота', '旋转测试', '旋轉測試', 'Döndürme Testi', 'Test obrotu'],
    'Recording for 30 seconds. Open an app that rotates, such as Safari, then turn the phone to the left, to the right and back upright, pausing at each. Then come back here and tap Share Log.': [
        'Aufzeichnung für 30 Sekunden. Öffne eine App, die sich drehen lässt, z. B. Safari, und drehe das iPhone nach links, nach rechts und wieder aufrecht, jeweils mit einer kurzen Pause. Komm dann zurück und tippe auf „Protokoll teilen“.',
        'Grabando durante 30 segundos. Abre una app que gire, como Safari, y gira el teléfono a la izquierda, a la derecha y de nuevo en vertical, con una pausa en cada posición. Después vuelve aquí y toca «Compartir registro».',
        'Enregistrement pendant 30 secondes. Ouvrez une app qui pivote, comme Safari, puis tournez le téléphone vers la gauche, vers la droite et de nouveau à la verticale, en marquant une pause à chaque fois. Revenez ensuite ici et touchez « Partager le journal ».',
        'Registrazione per 30 secondi. Apri un’app che ruota, come Safari, poi ruota il telefono a sinistra, a destra e di nuovo in verticale, fermandoti un attimo ogni volta. Poi torna qui e tocca «Condividi registro».',
        '30秒間記録します。Safariなど回転するAppを開き、端末を左、右、縦向きの順に回し、それぞれ少し止めてください。その後ここに戻り「ログを共有」をタップしてください。',
        '30초 동안 기록합니다. Safari처럼 회전하는 앱을 열고 기기를 왼쪽, 오른쪽, 다시 세로로 돌리며 각각 잠시 멈추세요. 그런 다음 여기로 돌아와 ‘로그 공유’를 탭하세요.',
        'Opname van 30 seconden. Open een app die draait, zoals Safari, en draai de telefoon naar links, naar rechts en weer rechtop, met telkens een korte pauze. Kom daarna terug en tik op ‘Log delen’.',
        'Gravando por 30 segundos. Abra um app que gire, como o Safari, e gire o telefone para a esquerda, para a direita e de volta à posição vertical, pausando em cada uma. Depois volte aqui e toque em “Compartilhar registro”.',
        'Запись в течение 30 секунд. Откройте приложение, которое поворачивается, например Safari, поверните телефон влево, вправо и обратно вертикально, задерживаясь в каждом положении. Затем вернитесь сюда и нажмите «Поделиться журналом».',
        '录制 30 秒。请打开会旋转的 App（如 Safari），将手机向左、向右转，再转回竖直，每次稍作停顿。然后回到这里轻点“共享日志”。',
        '錄製 30 秒。請打開會旋轉的 App（例如 Safari），將手機向左、向右轉，再轉回直立，每次稍作停頓。然後回到這裡點一下「分享記錄」。',
        '30 saniye kaydediliyor. Safari gibi dönen bir uygulama açın, telefonu sola, sağa ve tekrar dik konuma çevirin, her birinde kısa bir süre bekleyin. Sonra buraya dönüp “Günlüğü Paylaş”a dokunun.',
        'Nagrywanie przez 30 sekund. Otwórz aplikację, która się obraca, np. Safari, obróć telefon w lewo, w prawo i z powrotem pionowo, zatrzymując się na chwilę w każdej pozycji. Potem wróć tutaj i stuknij „Udostępnij dziennik”.',
    ],
    'OK': ['OK', 'OK', 'OK', 'OK', 'OK', '확인', 'OK', 'OK', 'ОК', '好', '好', 'Tamam', 'OK'],
    'Status': ['Status', 'Estado', 'État', 'Stato', '状態', '상태', 'Status', 'Estado', 'Состояние', '状态', '狀態', 'Durum', 'Stan'],
    'Detailed Logging': ['Detailliertes Protokoll', 'Registro detallado', 'Journal détaillé', 'Registro dettagliato', '詳細なログ', '상세 로그', 'Gedetailleerd log', 'Registro detalhado', 'Подробный журнал', '详细日志', '詳細記錄', 'Ayrıntılı Günlük', 'Szczegółowy dziennik'],
    'Share Log': ['Protokoll teilen', 'Compartir registro', 'Partager le journal', 'Condividi registro', 'ログを共有', '로그 공유', 'Log delen', 'Compartilhar registro', 'Поделиться журналом', '共享日志', '分享記錄', 'Günlüğü Paylaş', 'Udostępnij dziennik'],
    'Try Again': ['Erneut versuchen', 'Reintentar', 'Réessayer', 'Riprova', '再試行', '다시 시도', 'Opnieuw proberen', 'Tentar novamente', 'Повторить', '重试', '再試一次', 'Tekrar Dene', 'Spróbuj ponownie'],
    'Active': ['Aktiv', 'Activo', 'Actif', 'Attivo', '動作中', '활성', 'Actief', 'Ativo', 'Активен', '运行中', '運作中', 'Etkin', 'Aktywny'],
    'Off': ['Aus', 'Desactivado', 'Désactivé', 'Disattivato', 'オフ', '끔', 'Uit', 'Desativado', 'Выключен', '已关闭', '已關閉', 'Kapalı', 'Wyłączony'],
    'Paused': ['Pausiert', 'En pausa', 'En pause', 'In pausa', '一時停止中', '일시 정지됨', 'Gepauzeerd', 'Pausado', 'Приостановлен', '已暂停', '已暫停', 'Duraklatıldı', 'Wstrzymany'],
    'Unsupported': ['Nicht unterstützt', 'No compatible', 'Non pris en charge', 'Non supportato', '非対応', '지원되지 않음', 'Niet ondersteund', 'Não compatível', 'Не поддерживается', '不支持', '不支援', 'Desteklenmiyor', 'Nieobsługiwany'],
    'Not Running': ['Nicht aktiv', 'Sin ejecutar', 'Inactif', 'Non in esecuzione', '未実行', '실행 안 됨', 'Niet actief', 'Não em execução', 'Не запущен', '未运行', '未執行', 'Çalışmıyor', 'Nie działa'],
    # Value units and text set in code
    's': ['s', 's', 's', 's', '秒', '초', 's', 's', 'с', '秒', '秒', 'sn', 's'],
    'px': ['px'] * 13,
    '%': ['%'] * 13,
    'Selected': ['Ausgewählt', 'Seleccionadas', 'Sélectionnées', 'Selezionate', '選択済み', '선택됨', 'Geselecteerd', 'Selecionados', 'Выбранные', '已选择', '已選取', 'Seçilenler', 'Wybrane'],
    'Enter Value': ['Wert eingeben', 'Introducir valor', 'Saisir une valeur', 'Inserisci valore', '値を入力', '값 입력', 'Waarde invoeren', 'Inserir valor', 'Введите значение', '输入数值', '輸入數值', 'Değer Girin', 'Wpisz wartość'],
    'From %1$@ to %2$@.': ['Von %1$@ bis %2$@.', 'De %1$@ a %2$@.', 'De %1$@ à %2$@.', 'Da %1$@ a %2$@.', '%1$@〜%2$@', '%1$@~%2$@', 'Van %1$@ tot %2$@.', 'De %1$@ a %2$@.', 'От %1$@ до %2$@.', '%1$@ 至 %2$@', '%1$@ 至 %2$@', '%1$@ ile %2$@ arası.', 'Od %1$@ do %2$@.'],
    'Cancel': ['Abbrechen', 'Cancelar', 'Annuler', 'Annulla', 'キャンセル', '취소', 'Annuleer', 'Cancelar', 'Отмена', '取消', '取消', 'Vazgeç', 'Anuluj'],
    'Set': ['Übernehmen', 'Aplicar', 'Valider', 'Imposta', '設定', '설정', 'Stel in', 'Definir', 'Готово', '设定', '設定', 'Ayarla', 'Ustaw'],
}

# The button, read by the tweak in SpringBoard
TWEAK = {
    'Rotate?': ['Drehen?', '¿Girar?', 'Pivoter ?', 'Ruotare?', '回転？', '회전?', 'Draaien?', 'Girar?', 'Повернуть?', '旋转？', '旋轉？', 'Döndür?', 'Obrócić?'],
    'Cancel?': ['Abbrechen?', '¿Cancelar?', 'Annuler ?', 'Annullare?', 'キャンセル？', '취소?', 'Annuleren?', 'Cancelar?', 'Отменить?', '取消？', '取消？', 'İptal?', 'Anulować?'],
    'Rotate screen': ['Bildschirm drehen', 'Girar pantalla', 'Faire pivoter l’écran', 'Ruota schermo', '画面を回転', '화면 회전', 'Draai scherm', 'Girar tela', 'Повернуть экран', '旋转屏幕', '旋轉螢幕', 'Ekranı döndür', 'Obróć ekran'],
    'Cancel rotation': ['Drehen abbrechen', 'Cancelar giro', 'Annuler la rotation', 'Annulla rotazione', '回転をキャンセル', '회전 취소', 'Annuleer draaien', 'Cancelar rotação', 'Отменить поворот', '取消旋转', '取消旋轉', 'Döndürmeyi iptal et', 'Anuluj obrót'],
}

def check_coverage():
    root = plistlib.load(open(os.path.join(RESOURCES, 'Root.plist'), 'rb'))
    needed = set()
    for item in root['items']:
        for key in ('label', 'footerText', 'inlineLabel', 'valueSuffix'):
            if key in item: needed.add(item[key])
        needed.update(item.get('validTitles', []))
    missing = sorted(needed - set(ROOT))
    if missing:
        sys.exit('No translation for: ' + ', '.join(repr(m) for m in missing))
    for table in (ROOT, TWEAK):
        for english, translated in table.items():
            if len(translated) != len(LANGUAGES):
                sys.exit(f'{english!r}: {len(translated)} translations, expected {len(LANGUAGES)}')

def main():
    check_coverage()
    for i, language in enumerate(LANGUAGES):
        folder = os.path.join(RESOURCES, language + '.lproj')
        os.makedirs(folder, exist_ok=True)
        for name, table in (('Root', ROOT), ('Tweak', TWEAK)):
            strings = {english: translated[i] for english, translated in table.items()}
            with open(os.path.join(folder, name + '.strings'), 'wb') as f:
                plistlib.dump(strings, f, fmt=plistlib.FMT_XML, sort_keys=True)
    # English too: iOS only picks from the languages a bundle lists, so without an English folder an
    # English phone would get whichever other language comes next in its language list
    folder = os.path.join(RESOURCES, 'en.lproj')
    os.makedirs(folder, exist_ok=True)
    for name, table in (('Root', ROOT), ('Tweak', TWEAK)):
        with open(os.path.join(folder, name + '.strings'), 'wb') as f:
            plistlib.dump({english: english for english in table}, f, fmt=plistlib.FMT_XML, sort_keys=True)
    print(f'English + {len(LANGUAGES)} languages, {len(ROOT)} settings strings, {len(TWEAK)} button strings')

if __name__ == '__main__':
    main()
