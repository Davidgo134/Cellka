# Cellka

**Cellka** — open-source мобильное приложение для мониторинга и картирования сотовых сетей, аналог NetMonster / Cell Mapper, но со спутниковыми картами **Yandex MapKit** (с возможностью fallback на Google Maps).

## Идея проекта

Классические cell-mapping приложения (NetMonster, Cell Mapper, OpenSignal) показывают данные о базовых станциях (LAC/TAC, CID, PCI, RSRP/RSRQ/SINR, технологию радиосети) поверх обычных схематичных карт. Cellka делает то же самое, но:

- показывает данные поверх **спутникового/гибридного слоя карты**, чтобы видеть реальный рельеф, застройку и вышки на местности;
- в качестве картографического движка использует официальный **Yandex MapKit Mobile SDK** — легальный способ встраивания спутниковых снимков в приложение (в отличие от скрапинга тайлов, который запрещён правилами Яндекса);
- строит heatmap покрытия сети на основе накопленных измерений;
- хранит историю измерений локально (SQLite) и позволяет экспортировать/импортировать данные (CSV/GeoJSON).

## Почему Yandex MapKit, а не Google Maps

| Критерий | Yandex MapKit | Google Maps SDK |
|---|---|---|
| Качество спутниковых снимков в РФ/СНГ | Высокое, регулярно обновляется | Среднее в отдалённых регионах |
| Бесплатный лимит запросов | Выше для проектов в РФ/СНГ | Требует billing-аккаунт |
| Легальность встраивания в приложение | Да, через официальный SDK | Да, через официальный SDK |
| Глобальное покрытие вне СНГ | Слабее | Сильнее |
| Интеграция с Flutter | Пакет `yandex_mapkit` | Готовый плагин `google_maps_flutter` |

Вывод: для аудитории в РФ/СНГ Yandex MapKit даёт лучшее качество снимков и более гибкие условия использования, поэтому выбран как основной провайдер карт. Слой карт вынесен в отдельный интерфейс (`MapProvider`), чтобы можно было подключить Google Maps или Mapbox как альтернативу для других регионов без переписывания всего приложения.

## Функциональность (roadmap)

Прогресс по MVP отслеживается в [docs/MVP_PLAN.md](docs/MVP_PLAN.md).

- [ ] Чтение данных о соте (LAC/TAC, CID, PCI, band, RSRP/RSRQ/RSSI/SINR) через `TelephonyManager`
- [ ] Отображение текущей соты и соседних сот на спутниковой карте
- [ ] Запись трека измерений с привязкой к GPS-координатам
- [ ] Heatmap покрытия сети (по цвету — уровень сигнала)
- [ ] Экспорт треков в GeoJSON/CSV
- [ ] Тёмная тема, поддержка RU/EN

## Технологический стек

- **Flutter** (Dart) — кроссплатформенный UI
- **Yandex MapKit Mobile SDK** (пакет `yandex_mapkit`) — спутниковые/гибридные карты
- **Kotlin** (Android platform channel) — доступ к телефонии низкого уровня (`TelephonyManager`, `CellInfo`)
- **sqflite** — локальное хранилище измерений
- **geolocator** — GPS-трекинг
- **provider** — управление состоянием

## Структура проекта

```
Cellka/
├── .github/workflows/      # CI: analyze/test + сборка debug APK
├── android/                # нативный Android-код, доступ к TelephonyManager
├── lib/
│   ├── core/
│   │   ├── models/          # модели данных (CellInfo)
│   │   ├── map/              # абстракция MapProvider (Yandex/Google)
│   │   └── storage/          # работа с sqflite
│   ├── features/
│   │   ├── map_screen/       # экран карты с наложением сот
│   │   ├── cell_details/     # детали соты
│   │   └── history/          # история измерений, экспорт
│   └── main.dart
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DESIGN.md
│   └── MVP_PLAN.md
├── test/
├── pubspec.yaml
└── README.md
```

## Начало работы

```bash
git clone https://github.com/Davidgo134/Cellka.git
cd Cellka

# Догенерировать недостающие файлы (gradle wrapper jar, иконки) —
# существующие файлы не будут перезаписаны:
flutter create --platforms=android --project-name cellka --org com.github.davidgo134 .

# Прописать API-ключ Yandex MapKit (получить: https://developer.tech.yandex.ru/):
echo "MAPKIT_API_KEY=ВАШ_КЛЮЧ" >> android/local.properties

flutter pub get
flutter run
```

## CI

Workflow [.github/workflows/android.yml](.github/workflows/android.yml) на каждый push в `main`:
1. `flutter analyze` + `flutter test`
2. Сборка debug APK → артефакт `cellka-debug-apk`

Для сборки с рабочей картой добавьте секрет `YANDEX_MAPKIT_API_KEY` в Settings → Secrets and variables → Actions. Без секрета APK соберётся, но карта не загрузится.

## Лицензия

MIT — см. [LICENSE](LICENSE).

## Дисклеймер

Проект использует спутниковые снимки исключительно через официальный SDK Yandex MapKit в соответствии с условиями использования Яндекса. Прямой скрапинг/кэширование тайлов вне SDK запрещён правилами сервиса.
