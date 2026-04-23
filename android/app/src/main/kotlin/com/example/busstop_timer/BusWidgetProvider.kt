package com.example.busstop_timer // 본인 패키지명으로 수정

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class BusWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                // 플러터에서 'bus_info'라는 이름으로 보낸 데이터를 화면에 표시
                setTextViewText(R.id.widget_text, widgetData.getString("bus_info", "정보 없음"))
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}