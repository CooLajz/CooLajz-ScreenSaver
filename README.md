# Atlas · CooLajz ScreenSaver

Experimentální spořič pro macOS 13 a novější. Jemné barevné čáry společně proměňují kruhy, hvězdice, mnohoúhelníky, osmičky, listové tvary, astroidy a zaoblené čtverce. Generativní ornament má vlastní proměnlivou strukturu, rozvíjí se za obrys a vrací dovnitř. Černé pozadí zůstává součástí kompozice.

ARose inspiroval jemnost, barevnost a princip společně řízených parametrů. Atlas mapuje proměnlivé harmonické pole do otevřených i uzavřených geometrických profilů. Všechna vlákna sdílejí společné pole a dvojici aktuálních obrysů; ornament a morphování hlavního tvaru mají nezávislé časové průběhy.

Obrys kruhu má konstantní poloměr; u hvězdic a mnohoúhelníků se poloměr získá průsečíkem paprsku s hranou. Osmička používá Geronovu lemniskátu s proměnlivými proporcemi obou laloků. Listové profily mají harmonicky proměnný poloměr, astroida prohnuté strany a zaoblený čtverec vychází ze superelipsy. Plynule se interpolují odpovídající body dvou aktuálních profilů.

Paletu doplňuje větvená šestiramenná vločka, srdcovka a prostorový toroidální uzel, jehož náklon se v projekci průběžně mění. Dva vzácnější profily, široká zvlněná stuha a spirála, mají volné konce. Uzavřený motiv se při přechodu kreslí po postupně kratším úseku svého obvodu, zatímco se jeho body přesouvají na otevřenou křivku. Stopy a blízká barevná vlákna kolem ní vytvářejí závoj. Otevřené profily nenásledují přímo po sobě.

Ornament vzniká ze základního kruhového pohybu a tří dalších harmonických složek. Jejich celočíselné frekvence zahrnují oba směry oběhu. Vlastní fáze a normalizované váhy jednotlivých složek se vyvíjejí nezávisle na morphování hlavního obrysu. Dvě generované sady frekvencí se průběžně prolínají; neinterpolují se samotná celočíselná vinutí, takže uzavřené křivky zůstávají beze švu. Počet laloků ornamentu není předepsaný hlavním tvarem.

Třináct ornamentálních vláken sdílí stejné harmonické pole, ale liší se mírou deformace, fázovým posunem a poloměrem. Jejich rozestupy i soustředění se také průběžně mění. Hlavní čtrnácté vlákno drží čitelný obrys. Radiální transformace umožňuje přecházet dovnitř a vně profilu; vnější ornament zachovává proměnlivou radiální strukturu i během rozvíjení.

ARose inspiroval nezávislý vývoj frekvence, poloměrů a fází. Atlas původní řídicí tabulky ani zdrojové soubory nepřebírá. Kruh zůstává kruhový a čtverec čtvercový i na širokém monitoru; obdélníky a elipsy mají generované proporce, které se přizpůsobují dostupné ploše.

## Spuštění náhledu

S nainstalovaným Xcode spusťte:

```sh
./script/build_and_run.sh
```

Výstupem jsou `dist/CooLajz ScreenSaver.app` s vloženým rozšířením `AtlasExtension.appex` a kompatibilní `dist/Atlas.saver`. Aplikace otevře živý náhled. Jde o místní vývojové sestavení s ad hoc podpisem, zatím bez notarizovaného instalačního balíčku.

Pro samotné sestavení bez spuštění použijte `./script/build_and_run.sh --build`.

Pro běžné používání spusťte `./script/install_local.sh`. Aplikace se přesune do `/Applications`, případná předchozí instalace se nejprve zálohuje do `/private/tmp` a při spuštění se zaregistruje vložené rozšíření. V nabídce **Kresba → Nastavení systémového spořiče…** otevřete nastavení macOS a zvolte **Atlas**. Na macOS 13 použijte přiložený `Atlas.saver`; od macOS 14 se používá rozšíření přímo z aplikace.

Rozšíření používá stejné neveřejné rozhraní `com.apple.screensaver` jako ARose. Jde o praktickou místní integraci, která může vyžadovat úpravu po změně macOS. Klasický `.saver` zůstává samostatnou kompatibilní variantou.

## Použití kresby v jiném projektu

- [AtlasField.swift](Sources/Core/AtlasField.swift) generuje obrysy, harmonická vlákna a jejich proměny v čase.
- [AtlasPlayback.swift](Sources/Core/AtlasPlayback.swift) řídí tempo a pozastavení animace.
- [AtlasRenderer.swift](Sources/Core/AtlasRenderer.swift) a [AtlasShaders.swift](Sources/Core/AtlasShaders.swift) vykreslují barevné stopy a záři přes Metal.

Pro webový port vyjděte z generátoru tvarů a převeďte vykreslování z Metalu například do WebGL 2. Tento repozitář obsahuje nativní implementaci pro macOS.

## Živé pozadí plochy

V liště aplikace nebo v nabídce **Kresba** zapněte **Živé pozadí plochy**. Kresba se přesune pod ikony hlavního monitoru a přestane zachytávat myš i klávesnici. Ovládání najdete v menu baru pod ikonou jisker: vzhled, ruční pauza, nová kresba a **Návrat do okna**. Režim se pamatuje pro další spuštění. Volba **Spouštět po přihlášení** je volitelná a aktivuje se jen na výslovné zapnutí v nabídce.

Při překrytí aplikací nebo videem přes celou obrazovku se živé pozadí plynule zastaví; při návratu se během dvou sekund rozjede. Zamčení, neaktivní relace, uspání displeje a vlastní nebo jiný systémový spořič vyvolají okamžitou pauzu. Po zastavení se neodesílají další snímky na GPU. Detekce využívá systémová oznámení a metadata o rozměrech oken, bez snímání obrazovky a bez požadavku na zpřístupnění. V okně se pozastavuje také skrytý nebo minimalizovaný náhled. Ruční pauza se zachová i po návratu z celé obrazovky.

Systémový spořič má vlastní volby v Nastavení systému; v sandboxovaném rozšíření jsou oddělené od vzhledu aplikace a živého pozadí, stejně jako v ARose. Obě podoby používají stejnou matematiku a renderer. Záložky vývoje jsou oddělené, aby si současně spuštěná aplikace a systémový spořič nepřepisovaly stav. V klidovém systémovém náhledu se používá statický snímek; skutečný spořič se spouští přímo do Metal vykreslování.

Vlastní ikona je v `Resources/Atlas-Icon.png`; její zdrojový prompt a původ jsou v `Resources/Atlas-Icon.prompt.txt`. Systémový soubor `Atlas.icns` lze obnovit přes `./script/make_icon.sh`.

Ovládání:

- **Mezerník**: pozastavení / pokračování.
- **N**: nová samostatná kresba.
- **F**: celá obrazovka; **Esc**: návrat do okna.
- **Posuvníky v liště**: rychlost, délka tvaru, doznívání, světelnost, síla čáry a záře.
- **⌘S**: uložení snímku.

Nastavení se ukládá pro příslušný režim. Aplikace průběžně uchovává počáteční stav a čas vývoje kresby. Při dalším spuštění pokračuje geometrický vývoj; obrazová stopa z posledního okamžiku se vytvoří znovu. Při změně poměru stran se stejný obrazec přizpůsobí nové ploše.

**Světelnost** mění jas samotných vláken. **Záře** v rozsahu 0–100 % přidává měkké barevné světlo do jejich okolí; při 0 % zůstává ostrá kresba. Oba ovladače fungují i při pozastavené animaci a neposouvají obrazec. Při prvním načtení starších nastavení se poloha původního posuvníku záře převede na nový rozsah; ostatní hodnoty zůstanou zachované.

**Rychlost** má rozsah 1–10× a výchozí tempo je 1×. Nové 1× odpovídá původním 6×, nové 5× původním 12× a nové 10× původním 24×. Mezi těmito body tempo roste plynule. Ovládá vlákna, jejich vnitřní vývoj, barvy a rotaci. Uložené tempo zůstává zachované v mezích nového rozsahu; pomalejší hodnoty se zvednou na nové minimum 1×.

Čas od času se vlákna ve výchozím nastavení na 15 sekund poskládají do místního času ve formátu HH:MM. Při některých zobrazeních se pod ním objeví i datum DD.MM.RRRR. Oba řádky zůstávají vodorovné, zatímco se kompozice posouvá a mění velikost. Při změně minuty se mění jen potřebné tahy. První automatické zobrazení přichází po 5 až 7 minutách a 20 sekundách skutečného přehrávání. Po zapnutí volby **Zobrazovat hodiny** lze nastavit nejkratší a nejdelší čekání před prvním i mezi dalšími zobrazeními (30 sekund až 30 minut) a celkovou délku zobrazení včetně přechodů (8 až 90 sekund). Jas číslic pulzuje po jednotlivých vláknech. Pro okamžitou ukázku je v nabídce Kresba i v nabídce živého pozadí položka **Zobrazit čas a datum**.

**Délka tvaru** má rozsah 3–40 sekund a výchozí hodnotu přibližně 8 sekund mezi dvěma cílovými tvary. První pětinu intervalu se obrys krátce drží svého tvaru, poté plynule přejde do dalšího; jemné časové modulace délku jednotlivých intervalů mírně obměňují. Vlákna pokračují i během setrvání a rotace má vlastní průběh. Posuvník je nezávislý na rychlosti kresby a změna za běhu neposune aktuální obrazec. Samostatný čas proměn se ukládá společně s vývojem ornamentu.

## Dlouhý průběh

Cílové profily a jejich parametry generátor průběžně odvozuje z počátečního stavu a postupujícího čítače. Mění se například počet cípů, hloubka hvězdic, počet a hloubka listů, proporce obdélníků a elips, tvar laloků osmičky a zakulacení čtverců. Výsledek lze přímo obnovit z uloženého času a počátečního stavu bez přehrávání předchozích snímků.

Hlavní morphování a přechody mezi sadami harmonických frekvencí mají samostatné monotónní časové průběhy. Přechod používá `m(u) = 6u⁵−15u⁴+10u³`, jehož první i druhá derivace jsou na koncích nulové. Jednotlivé složky ornamentu, jejich váhy, rozestupy vrstev, radiální rozvíjení a společná rotace mají další vlastní fáze. Rychlosti některých fází vycházejí z různých odmocnin prvočísel. Žádná společná krátká smyčka se při dokončení morphingu ani ornamentu nespouští znovu.

Vnitřní pohyb pokračuje i při zpomalení samotného morphingu. Jedna složka může být dominantní a tvořit čitelnou rozetu; postupným převážením dalších složek vznikají jiné smyčky, protisměrné struktury a propletení. Veškerá vlákna dál vycházejí ze společného pole.

Rotace má samostatnou generovanou dráhu s různými délkami úseků, rychlostmi, oběma směry a skutečným setrváním na stejném úhlu. Při změně tempa ve stejném směru může pokračovat bez zastavení. Obrácení směru prochází nulovou rychlostí a nulovým zrychlením; po klidovém úseku může následovat původní i opačný směr. Úhly spojuje kvintická Hermitova křivka se společnými tečnami a návazností druhé derivace. Délky úseků zohledňují velikost natočení a omezují nejvyšší rychlost. Průběh se přímo obnoví z času a počátečního stavu bez sčítání předchozích otoček. Klid rotace nepozastavuje ornament ani morphování.

Rozvíjení dovnitř a ven sleduje generovanou dráhu mezi různými hloubkami. Délky přesunů se výrazně liší; některé úseky drží stejnou polohu nebo efekt zcela vypnou. Křivka mezi polohami má nulovou první i druhou derivaci na spojích, takže i rychlé výpady plynule začínají a končí. Sousední vlákna mají společný hladký gradient přesahu. Dráha je nezávislá na proměnách hlavního tvaru a obnovuje se z uloženého času. Vypnutí rozvíjení neovlivňuje vlastní průběh ornamentu, rotace a morphování.

Vnější poloměry mají měkké prostorové omezení; rámování zachovává stálou rezervu kolem obrysu. Pohyb vláken tak neřídí přibližování a oddalování celé kompozice. Přizpůsobení různým profilům a natočení dál zajišťuje využití dostupné plochy.

To není záruka vizuálně jedinečného obrazu v každém okamžiku. Příbuzné geometrické rodiny se mohou vracet a konečná numerická přesnost neumožňuje slibovat konkrétní počet let do opakování. Rozmanitost se proto ověřuje také na samotné kresbě po odstranění vlivu obrysu, barvy, společné rotace a měřítka.

Metal každý snímek vykreslí 14 provázaných vláken a nechá předchozí polohy krátce doznít. Výchozí čára má sílu 0,6 bodu a exponenciální doznívání s časovou konstantou 0,55 sekundy. Barevné tělo doplňuje úzké světelné jádro a dva pomalu putující světelné akcenty. Výchozí světelnost je 135 % a záře 55 %.

Polohy segmentů, morphing, vykreslení, doznívání a záři zpracovává GPU přes Metal. CPU připravuje společné časové parametry, přizpůsobení plochy a příkazy pro GPU. Náhled i systémový spořič používají stejný renderer s cílem 30 snímků za sekundu. Při běžném vykreslování se obrazová historie nečte zpět do CPU; tento přenos se používá pro snímky a diagnostické video.

Obrazová historie používá dvě textury s 16bitovými plovoucími složkami. Z jasných částí kresby vzniká blízké a vzdálenější měkké halo. Gaussian filtry pracují na GPU ve čtvrtinové šířce i výšce obrazu; jejich čtyři pracovní textury se opakovaně používají. Při nulové záři se tyto průchody vynechají. Světlo se sčítá v lineárním prostoru a po řízení expozice se převádí do sRGB. Komprese jasů zachovává poměry barevných složek, aby se nejsvětlejší partie zbytečně neslévaly do bílé.

## Ověření

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --check
./script/build_and_run.sh --lighting-check
./script/build_and_run.sh --timing-check
./script/build_and_run.sh --geometry-gallery
./script/build_and_run.sh --morph-preview
./script/test_integration.sh
```

Kontrola vzorkuje konce otevřených i uzavřených vláken a prostorové meze na čtvercové, širokoúhlé i portrétní ploše během 24 hodin matematického času. Samostatně ověřuje návaznost cílových profilů a harmonických sad, průběžný vnitřní pohyb, přesun vláken dovnitř i ven a společný střed osmičky. Dále vykreslí 15 minut Metal animace a ověří tempa 1× i 10×. Výstupy jsou v `.build/checks/`.

Kontrola časování ověřuje nezávislost rychlosti ornamentu a délky tvaru, plynulé ukončení setrvání a zachování starších nastavení. Změna délky tvaru při pozastavení musí zachovat pixelově shodný obraz i oba časy.

Integrační kontrola ověřuje priority pauz a brzdění při 30–144 Hz, runtime rozhraní rozšíření, skutečné Metal snímky při start/stop, zachování obrazu při opakovaném startu a opakované otevírání voleb. Skutečné zamčení a uspání počítače se při automatickém testu nevyvolává.

Kontrola rozvíjení sleduje 160 navazujících intervalů, rozdíly v jejich rychlosti, skutečné setrvání i vypnutí efektu. Ověřuje návaznost také na hranicích časových bloků a stálé měřítko stejného hlavního obrysu. Průběh ukládá do `excursion-timing.csv`.

Kontrola rotace sleduje 128 úseků pro každý ze tří počátečních stavů. Ověřuje oba směry, klidové úseky, pokračování stejným i opačným směrem po klidu, návaznost úhlu, rychlosti i zrychlení a nezávislý pohyb ornamentu. Průběh ukládá do `rotation-timing.csv`.

Rozmanitost ornamentu se kontroluje na stejném kruhovém obrysu během jedné reálné hodiny při tempu 6×. Porovnává se úhlové spektrum křivek normalizované vůči celkovému měřítku a nezávislé na společném natočení; barvy, proměny obrysu a vnější rozvíjení se z porovnání vyřadí. Výsledkem je soubor `intrinsic-hour.csv`. Tento test dokládá změny vnitřní struktury, ne estetickou kvalitu ani zaručenou dobu do opakování.

Galerie `.build/morph-gallery/` obsahuje okamžiky dlouhého vývoje a čtyři skutečně vykreslené snímky stejného kruhu se zmrazenou společnou rotací a měřítkem. Odpovídají přibližně začátku, 5, 30 a 60 minutám při tempu 6×. Video `.build/morph-preview/morph-preview.mp4` ukazuje prvních 348 sekund matematického vývoje v 58 sekundách. Vzniká přímo z Metal snímků systémovým kodérem H.264 se stejnými 30 snímky za sekundu jako nativní náhled.

Kontrola světla porovnává stejný pozastavený obrazec při záři 0 a 100 %, ověřuje viditelné halo a změnu světelnosti. Po návratu na nulovou záři musí být snímek pixelově shodný s výchozím. Čas a geometrie se během porovnání nesmějí posunout. Ověřuje se rovněž Retina vykreslování a zachování starších nastavení. Srovnávací snímky jsou v `.build/lighting-checks/`.
