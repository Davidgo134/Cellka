# towerdb — комбинированная база сотовых вышек

ETL-инструмент для сборки единой базы координат базовых станций из открытых источников.
Результат — компактный `cellka_towers.sqlite`, который приложение Cellka использует
для lookup координат вышки по `MCC/MNC/TAC(LAC)/CI`.

## Источники

| Источник | Ссылка | Лицензия | Формат |
|---|---|---|---|
| OpenCelliD | https://opencellid.org/downloads | CC BY-SA 4.0 | CSV: `radio,mcc,net,area,cell,unit,lon,lat,range,samples,changeable,created,updated,averageSignal` |
| MLS (архив) | дампы на archive.org (`MLS-full-cell-export`) | CC0 | тот же формат, что OpenCelliD |
| openBmap / radiocells.org | https://radiocells.org/downloads | ODbL | CSV с `;`: `lat;lon;mcc;mnc;lac;cellid` |

OpenStreetMap (мачты, `tower:type=communication`) в базу **не мержится**:
лицензия ODbL несовместима с CC BY-SA для смешанного датасета. OSM используется
в приложении отдельным слоем подсказок/верификации.

## Использование

Зависимостей нет — только Python 3.9+ stdlib.

```bash
# 1. Скачать дампы (OpenCelliD требует регистрацию, лимит 2 выгрузки/день на токен)
mkdir -p data && cd data
#   - opencellid.csv.gz          — full dump или выгрузка по MCC=250
#   - MLS-full-cell-export.csv.gz — архивный дамп MLS
#   - cells.csv                   — radiocells.org
cd ..

# 2. Инжест в сырой слой
python tools/towerdb/ingest.py --source opencellid towers.db data/opencellid.csv.gz
python tools/towerdb/ingest.py --source mls        towers.db data/MLS-full-cell-export.csv.gz
python tools/towerdb/ingest.py --source openbmap   towers.db data/cells.csv

# 3. Мерж с дедупликацией и confidence score
python tools/towerdb/merge.py towers.db

# 4. Экспорт компактной базы для приложения
python tools/towerdb/export.py towers.db --out cellka_towers.sqlite
```

## Confidence score

```
confidence = вес_источника
           + min(log10(samples+1)/3, 0.30)   # бонус за количество наблюдений
           + max(0, 0.20 - 0.05 × возраст_лет) # бонус за свежесть
           − 0.10 если range > 5000 м          # штраф за неточность
           + 0.20 если источники согласны (<1 км между точками)
```

Итоговая координата — взвешенный центроид по confidence всех записей ключа.

## Атрибуция (обязательна)

- OpenCelliD — CC BY-SA 4.0, https://opencellid.org
- openBmap / radiocells.org — ODbL, https://radiocells.org
- MLS — CC0 (архив)

Производная база, содержащая данные OpenCelliD, должна распространяться под CC BY-SA 4.0
с указанием источников. Мета-информация включается в `cellka_towers.sqlite` (таблица `meta`).
