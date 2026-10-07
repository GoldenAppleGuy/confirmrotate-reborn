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
