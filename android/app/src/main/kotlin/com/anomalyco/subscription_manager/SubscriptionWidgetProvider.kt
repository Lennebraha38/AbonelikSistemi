package com.anomalyco.subscription_manager

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Ana ekran widget'ı (App Widget). Flutter tarafı WidgetService ile
 * "widget_text" anahtarına biçimlendirilmiş metni yazar; burada RemoteViews
 * olarak çizilir ve dokunulunca uygulama açılır.
 */
class SubscriptionWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val prefs = HomeWidgetPlugin.getData(context)
            val text = prefs.getString("widget_text", "Sonraki 14 günde yenileme yok.")
                ?: "Sonraki 14 günde yenileme yok."
            val views = RemoteViews(context.packageName, R.layout.subscription_widget)
            views.setTextViewText(R.id.widget_text, text)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
