package com.github.davidgo134.cellka

import android.content.Context
import android.os.Build
import android.telephony.CellIdentityGsm
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellIdentityTdscdma
import android.telephony.CellIdentityWcdma
import android.telephony.CellInfo
import android.telephony.CellInfoCdma
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoTdscdma
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthNr
import android.telephony.TelephonyManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Плагин чтения данных о сотах через [TelephonyManager.getAllCellInfo].
 * MethodChannel: `cellka/telephony`.
 *
 * Методы:
 *  - `getAllCellInfo` — список всех видимых сот (обслуживающая + соседние);
 *  - `getOperatorInfo` — оператор, тип сети, роуминг.
 */
class CellInfoPlugin private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "cellka/telephony"
        private const val UNKNOWN = Int.MAX_VALUE

        fun registerWith(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(CellInfoPlugin(context.applicationContext))
        }

        /** Int.MAX_VALUE — маркер «значение недоступно» в Android CellInfo API. */
        private fun Int.valid(): Int? = takeIf { it != UNKNOWN }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAllCellInfo" -> getAllCellInfo(result)
            "getOperatorInfo" -> getOperatorInfo(result)
            else -> result.notImplemented()
        }
    }

    private fun getAllCellInfo(result: MethodChannel.Result) {
        try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            result.success(tm.allCellInfo.orEmpty().map { cellToMap(it) })
        } catch (e: SecurityException) {
            result.error(
                "PERMISSION_DENIED",
                "Нет разрешений ACCESS_FINE_LOCATION / READ_PHONE_STATE",
                e.message,
            )
        } catch (e: Exception) {
            result.error("CELL_INFO_ERROR", e.message, null)
        }
    }

    private fun getOperatorInfo(result: MethodChannel.Result) {
        try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            val type = tm.dataNetworkType
            result.success(
                mapOf(
                    "operatorName" to tm.networkOperatorName,
                    "simOperatorName" to tm.simOperatorName,
                    "networkOperator" to tm.networkOperator, // "25001" = MCC+MNC
                    "networkType" to type,
                    "networkTypeName" to networkTypeName(type),
                    "isRoaming" to tm.isNetworkRoaming,
                )
            )
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Нет разрешения READ_PHONE_STATE", e.message)
        } catch (e: Exception) {
            result.error("OPERATOR_ERROR", e.message, null)
        }
    }

    private fun cellToMap(info: CellInfo): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>("registered" to info.isRegistered)
        when (info) {
            is CellInfoLte -> map.putAll(lteToMap(info))
            is CellInfoWcdma -> map.putAll(wcdmaToMap(info))
            is CellInfoGsm -> map.putAll(gsmToMap(info))
            is CellInfoCdma -> map.putAll(cdmaToMap(info))
            else -> {
                // CellInfoNr / CellInfoTdscdma существуют только с API 29
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    when (info) {
                        is CellInfoNr -> map.putAll(nrToMap(info))
                        is CellInfoTdscdma -> map.putAll(tdscdmaToMap(info))
                        else -> map["technology"] = "UNKNOWN"
                    }
                } else {
                    map["technology"] = "UNKNOWN"
                }
            }
        }
        return map
    }

    private fun lteToMap(info: CellInfoLte): Map<String, Any?> {
        val id = info.cellIdentity
        val s = info.cellSignalStrength
        return mapOf(
            "technology" to "LTE",
            "mcc" to mccOf(id),
            "mnc" to mncOf(id),
            "tac" to id.tac.valid(),
            "ci" to id.ci.valid(),
            "pci" to id.pci.valid(),
            "earfcn" to id.earfcn.valid(),
            "bandwidth" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.bandwidth.valid() else null,
            "rsrp" to s.rsrp.valid(),
            "rsrq" to s.rsrq.valid(),
            "rssi" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) s.rssi.valid() else null,
            "sinr" to s.rssnr.valid(),
            "dbm" to s.dbm.valid(),
            "asu" to s.asuLevel.valid(),
            "ta" to s.timingAdvance.valid(),
        )
    }

    private fun nrToMap(info: CellInfoNr): Map<String, Any?> {
        val id = info.cellIdentity as CellIdentityNr
        val s = info.cellSignalStrength as CellSignalStrengthNr
        return mapOf(
            "technology" to "NR",
            "mcc" to id.mccString?.toIntOrNull(),
            "mnc" to id.mncString?.toIntOrNull(),
            "tac" to id.tac.valid(),
            "nci" to id.nci,
            "pci" to id.pci.valid(),
            "nrarfcn" to id.nrarfcn.valid(),
            "rsrp" to s.ssRsrp.valid(),
            "rsrq" to s.ssRsrq.valid(),
            "sinr" to s.ssSinr.valid(),
            "dbm" to s.dbm.valid(),
            "asu" to s.asuLevel.valid(),
        )
    }

    private fun wcdmaToMap(info: CellInfoWcdma): Map<String, Any?> {
        val id = info.cellIdentity
        val s = info.cellSignalStrength
        return mapOf(
            "technology" to "UMTS",
            "mcc" to mccOf(id),
            "mnc" to mncOf(id),
            "lac" to id.lac.valid(),
            "ci" to id.cid.valid(),
            "psc" to id.psc.valid(),
            "uarfcn" to id.uarfcn.valid(),
            "dbm" to s.dbm.valid(),
            "asu" to s.asuLevel.valid(),
        )
    }

    private fun gsmToMap(info: CellInfoGsm): Map<String, Any?> {
        val id = info.cellIdentity
        val s = info.cellSignalStrength
        return mapOf(
            "technology" to "GSM",
            "mcc" to mccOf(id),
            "mnc" to mncOf(id),
            "lac" to id.lac.valid(),
            "ci" to id.cid.valid(),
            "bsic" to id.bsic.valid(),
            "arfcn" to id.arfcn.valid(),
            "dbm" to s.dbm.valid(),
            "rssi" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) s.rssi.valid() else null,
            "asu" to s.asuLevel.valid(),
            "ta" to s.timingAdvance.valid(),
        )
    }

    private fun tdscdmaToMap(info: CellInfoTdscdma): Map<String, Any?> {
        val id = info.cellIdentity
        val s = info.cellSignalStrength
        return mapOf(
            "technology" to "TDSCDMA",
            "mcc" to id.mccString?.toIntOrNull(),
            "mnc" to id.mncString?.toIntOrNull(),
            "lac" to id.lac.valid(),
            "ci" to id.cid.valid(),
            "cpid" to id.cpid.valid(),
            "uarfcn" to id.uarfcn.valid(),
            "dbm" to s.dbm.valid(),
            "asu" to s.asuLevel.valid(),
        )
    }

    private fun cdmaToMap(info: CellInfoCdma): Map<String, Any?> {
        val id = info.cellIdentity
        val s = info.cellSignalStrength
        return mapOf(
            "technology" to "CDMA",
            "ci" to id.basestationId.valid(),
            "networkId" to id.networkId.valid(),
            "systemId" to id.systemId.valid(),
            "dbm" to s.cdmaDbm.valid(),
            "evdoDbm" to s.evdoDbm.valid(),
            "cdmaEcio" to s.cdmaEcio.valid(),
            "evdoSnr" to s.evdoSnr.valid(),
            "asu" to s.asuLevel.valid(),
        )
    }

    // MCC/MNC: до API 28 — int (deprecated), с API 28 — String
    @Suppress("DEPRECATION")
    private fun mccOf(id: CellIdentityLte): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString?.toIntOrNull() else id.mcc.valid()

    @Suppress("DEPRECATION")
    private fun mncOf(id: CellIdentityLte): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString?.toIntOrNull() else id.mnc.valid()

    @Suppress("DEPRECATION")
    private fun mccOf(id: CellIdentityWcdma): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString?.toIntOrNull() else id.mcc.valid()

    @Suppress("DEPRECATION")
    private fun mncOf(id: CellIdentityWcdma): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString?.toIntOrNull() else id.mnc.valid()

    @Suppress("DEPRECATION")
    private fun mccOf(id: CellIdentityGsm): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mccString?.toIntOrNull() else id.mcc.valid()

    @Suppress("DEPRECATION")
    private fun mncOf(id: CellIdentityGsm): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) id.mncString?.toIntOrNull() else id.mnc.valid()

    private fun networkTypeName(type: Int): String = when (type) {
        TelephonyManager.NETWORK_TYPE_GPRS -> "GPRS"
        TelephonyManager.NETWORK_TYPE_EDGE -> "EDGE"
        TelephonyManager.NETWORK_TYPE_CDMA -> "CDMA"
        TelephonyManager.NETWORK_TYPE_1xRTT -> "1xRTT"
        TelephonyManager.NETWORK_TYPE_IDEN -> "iDEN"
        TelephonyManager.NETWORK_TYPE_GSM -> "GSM"
        TelephonyManager.NETWORK_TYPE_UMTS -> "UMTS"
        TelephonyManager.NETWORK_TYPE_EVDO_0 -> "EVDO_0"
        TelephonyManager.NETWORK_TYPE_EVDO_A -> "EVDO_A"
        TelephonyManager.NETWORK_TYPE_HSDPA -> "HSDPA"
        TelephonyManager.NETWORK_TYPE_HSUPA -> "HSUPA"
        TelephonyManager.NETWORK_TYPE_HSPA -> "HSPA"
        TelephonyManager.NETWORK_TYPE_EVDO_B -> "EVDO_B"
        TelephonyManager.NETWORK_TYPE_EHRPD -> "eHRPD"
        TelephonyManager.NETWORK_TYPE_HSPAP -> "HSPA+"
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_IWLAN -> "IWLAN"
        TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "TD-SCDMA"
        TelephonyManager.NETWORK_TYPE_NR -> "NR" // константа инлайнится, безопасно на API < 29
        else -> "UNKNOWN($type)"
    }
}
