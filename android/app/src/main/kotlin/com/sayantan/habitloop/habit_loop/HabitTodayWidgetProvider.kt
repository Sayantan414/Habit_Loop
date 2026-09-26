package com.sayantan.habitloop.habit_loop

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * "Today" home screen widget: a progress ring (or a solid check badge once
 * every habit is done), the streak, today's habits, and a collapsible list of
 * pending to-dos.
 *
 * Data arrives from Flutter as two JSON snapshots written by WidgetService;
 * everything else — layout fitting, the to-do toggle, the ring — happens
 * natively so the widget stays responsive without waking the Flutter engine.
 */
class HabitTodayWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val habits = HabitsSnapshot.parse(widgetData.getString(KEY_HABITS, null))
        val todos = TodosSnapshot.parse(widgetData.getString(KEY_TODOS, null))
        val expanded = uiPrefs(context).getBoolean(KEY_TODOS_EXPANDED, true)
        val enabled = widgetData.getBoolean(KEY_ENABLED, true)
        for (id in appWidgetIds) {
            val views = if (enabled) {
                val options = appWidgetManager.getAppWidgetOptions(id)
                buildViews(context, options, habits, todos, expanded)
            } else {
                hiddenViews(context)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        // Resizing changes how many rows fit, so redraw that instance.
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE_TODOS) {
            val prefs = uiPrefs(context)
            val expanded = prefs.getBoolean(KEY_TODOS_EXPANDED, true)
            prefs.edit().putBoolean(KEY_TODOS_EXPANDED, !expanded).apply()

            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, HabitTodayWidgetProvider::class.java)
            )
            onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
            return
        }
        super.onReceive(context, intent)
    }

    // ------------------------------------------------------------------ render

    private fun buildViews(
        context: Context,
        options: Bundle,
        habits: HabitsSnapshot?,
        todos: TodosSnapshot,
        todosExpanded: Boolean
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        val today = dayKey(Calendar.getInstance())
        val isStale = habits != null && habits.day != today

        views.setOnClickPendingIntent(R.id.header, launch(context, "habitloop://today"))
        views.setOnClickPendingIntent(R.id.header_todo_column, launch(context, "habitloop://todo"))
        views.setTextViewText(
            R.id.header_label,
            "TODAY · " + SimpleDateFormat("EEE, d MMM", Locale.getDefault())
                .format(Calendar.getInstance().time).uppercase(Locale.getDefault())
        )

        renderHeader(context, views, habits, todos, isStale)

        // --- Row budget -----------------------------------------------------
        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        val heightDp = if (minH in 1 until maxH) minH else if (maxH > 0) maxH else 120
        var available = heightDp - FIXED_CHROME_DP

        val habitList = habits?.habits.orEmpty()
        val todoWant = when {
            !todosExpanded -> 0
            todos.count == 0 -> 1 // the "nothing pending" line
            else -> minOf(todos.items.size, TODO_SLOTS.size)
        }

        // Only show detailed list rows if the widget height is expanded (150dp+)
        var habitRows = 0
        if (heightDp >= 150 && habitList.isNotEmpty()) {
            val room = (available - HABITS_MARGIN_DP - todoWant * TODO_ROW_DP) / HABIT_ROW_DP
            habitRows = minOf(habitList.size, HABIT_SLOTS.size, maxOf(1, room))
            if ((available - HABITS_MARGIN_DP) / HABIT_ROW_DP < 1) habitRows = 0
            if (habitRows > 0) available -= HABITS_MARGIN_DP + habitRows * HABIT_ROW_DP
        }
        val todoRows = if (heightDp >= 150) minOf(todoWant, maxOf(0, available / TODO_ROW_DP)) else 0

        // --- Habits ---------------------------------------------------------
        views.setViewVisibility(R.id.habits_container, if (habitRows > 0) View.VISIBLE else View.GONE)
        val night = isNight(context)
        HABIT_SLOTS.forEachIndexed { i, slot ->
            val habit = habitList.getOrNull(i)
            if (habit == null || i >= habitRows) {
                views.setViewVisibility(slot.row, View.GONE)
                return@forEachIndexed
            }
            // A stale snapshot is from an earlier day: nothing is checked yet.
            val done = habit.done && !isStale
            views.setViewVisibility(slot.row, View.VISIBLE)
            views.setTextViewText(slot.title, habit.title)
            views.setTextColor(
                slot.title,
                context.getColor(if (done) R.color.widget_text_tertiary else R.color.widget_text_primary)
            )
            views.setInt(slot.dot, "setColorFilter", if (night) habit.colorDark else habit.colorLight)
            views.setImageViewResource(
                slot.status,
                if (done) R.drawable.ic_widget_check_circle else R.drawable.ic_widget_circle
            )
            views.setContentDescription(slot.status, if (done) "Done" else "Not done yet")
            views.setOnClickPendingIntent(
                slot.row,
                launch(context, "habitloop://habit?id=" + Uri.encode(habit.id))
            )
        }

        // --- To-dos ---------------------------------------------------------
        views.setViewVisibility(R.id.todo_section, if (heightDp >= 150) View.VISIBLE else View.GONE)
        views.setTextViewText(
            R.id.todo_count,
            if (todos.count == 0) "All clear" else "${todos.count} pending"
        )
        views.setImageViewResource(
            R.id.todo_toggle_icon,
            if (todosExpanded) R.drawable.ic_widget_collapse else R.drawable.ic_widget_expand
        )
        views.setContentDescription(
            R.id.todo_toggle_icon,
            if (todosExpanded) "Hide to-dos" else "Show to-dos"
        )
        views.setOnClickPendingIntent(R.id.todo_header, toggleTodos(context))
        views.setViewVisibility(R.id.todo_container, if (todoRows > 0) View.VISIBLE else View.GONE)

        val showEmpty = todosExpanded && todos.count == 0 && todoRows > 0
        views.setViewVisibility(R.id.todo_empty, if (showEmpty) View.VISIBLE else View.GONE)

        TODO_SLOTS.forEachIndexed { i, slot ->
            val todo = todos.items.getOrNull(i)
            if (todo == null || i >= todoRows || todos.count == 0) {
                views.setViewVisibility(slot.row, View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(slot.row, View.VISIBLE)
            views.setTextViewText(slot.title, todo.title)
            views.setOnClickPendingIntent(slot.row, launch(context, "habitloop://todo"))
        }

        return views
    }

    /**
     * Neutral card shown when the user turns the widget off in Settings: no
     * habit or to-do titles, just a way back into the app.
     */
    private fun hiddenViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        views.setImageViewResource(R.id.progress_ring, R.mipmap.ic_launcher)
        views.setContentDescription(R.id.progress_ring, "Habit Loop")
        views.setTextViewText(R.id.header_label, "HABIT LOOP")
        views.setTextViewText(R.id.progress_title, "Widget hidden")
        views.setTextViewText(R.id.progress_subtitle, "Turn it on in Settings")
        views.setViewVisibility(R.id.header_todo_column, View.GONE)
        views.setViewVisibility(R.id.habits_container, View.GONE)
        views.setViewVisibility(R.id.todo_section, View.GONE)
        views.setOnClickPendingIntent(R.id.widget_root, launch(context, "habitloop://today"))
        return views
    }

    private fun renderHeader(
        context: Context,
        views: RemoteViews,
        habits: HabitsSnapshot?,
        todos: TodosSnapshot,
        isStale: Boolean
    ) {
        val total = habits?.total ?: 0
        val done = if (isStale) 0 else habits?.done ?: 0
        val streak = habits?.streak ?: 0
        val allDone = total > 0 && done == total
        val todoCount = todos.count

        views.setImageViewBitmap(R.id.progress_ring, ringBitmap(context, done, total, allDone))
        views.setContentDescription(R.id.progress_ring, "$done of $total habits done today")

        // Right column: To-Do count
        views.setViewVisibility(R.id.header_todo_column, View.VISIBLE)
        val todoTitleText = when (todoCount) {
            0 -> "All clear"
            1 -> "1 pending"
            else -> "$todoCount pending"
        }
        views.setTextViewText(R.id.header_todo_title, todoTitleText)

        // Left column: Habits status & streak
        when {
            habits == null -> {
                views.setTextViewText(R.id.progress_title, "Habit Loop")
                views.setTextViewText(R.id.progress_subtitle, "Open app to start")
            }
            isStale -> {
                val yesterday = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
                val streakAlive = habits.day == dayKey(yesterday) &&
                    habits.total > 0 && habits.done == habits.total && streak > 0
                views.setTextViewText(R.id.progress_title, "A fresh day")
                if (streakAlive) {
                    views.setTextViewText(R.id.progress_subtitle, "🔥 $streak-day streak")
                    views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_warning))
                } else {
                    views.setTextViewText(R.id.progress_subtitle, "Tap to check in")
                    views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_text_secondary))
                }
            }
            total == 0 -> {
                views.setTextViewText(R.id.progress_title, "No habits")
                views.setTextViewText(R.id.progress_subtitle, "Tap to add one")
                views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_text_secondary))
            }
            allDone -> {
                views.setTextViewText(R.id.progress_title, "All habits done!")
                if (streak > 0) {
                    views.setTextViewText(R.id.progress_subtitle, "🔥 $streak-day streak")
                    views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_warning))
                } else {
                    views.setTextViewText(R.id.progress_subtitle, "Every habit checked off")
                    views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_text_secondary))
                }
            }
            else -> {
                val left = total - done
                views.setTextViewText(R.id.progress_title, "$done of $total done")
                if (streak > 0) {
                    views.setTextViewText(R.id.progress_subtitle, "🔥 $streak-day streak")
                    views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_warning))
                } else {
                    views.setTextViewText(R.id.progress_subtitle, "$left left today")
                    views.setTextColor(R.id.progress_subtitle, context.getColor(R.color.widget_text_secondary))
                }
            }
        }
    }

    /**
     * Flat progress ring, or a solid success badge with a check mark once the
     * day is complete. Drawn to a bitmap because RemoteViews has no arc view.
     */
    private fun ringBitmap(context: Context, done: Int, total: Int, allDone: Boolean): Bitmap {
        val density = context.resources.displayMetrics.density
        val size = (RING_DP * density).toInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val center = size / 2f

        if (allDone) {
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = context.getColor(R.color.widget_success)
            }
            canvas.drawCircle(center, center, center, fill)

            val check = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFFFFFFFF.toInt()
                style = Paint.Style.STROKE
                strokeWidth = 4f * density
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            val path = Path().apply {
                moveTo(size * 0.30f, size * 0.52f)
                lineTo(size * 0.44f, size * 0.66f)
                lineTo(size * 0.71f, size * 0.38f)
            }
            canvas.drawPath(path, check)
            return bitmap
        }

        val stroke = 5.5f * density
        val inset = stroke / 2f
        val oval = RectF(inset, inset, size - inset, size - inset)

        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = context.getColor(R.color.widget_track)
            style = Paint.Style.STROKE
            strokeWidth = stroke
        }
        canvas.drawArc(oval, 0f, 360f, false, track)

        if (total > 0 && done > 0) {
            val progress = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = context.getColor(R.color.widget_accent)
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.ROUND
            }
            canvas.drawArc(oval, -90f, 360f * done / total, false, progress)
        }

        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = context.getColor(R.color.widget_text_primary)
            textSize = 14f * density
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.CENTER
        }
        val text = if (total == 0) "–" else "$done/$total"
        val baseline = center - (label.descent() + label.ascent()) / 2f
        canvas.drawText(text, center, baseline, label)
        return bitmap
    }

    // ----------------------------------------------------------------- helpers

    private fun launch(context: Context, uri: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    private fun toggleTodos(context: Context): PendingIntent {
        val intent = Intent(context, HabitTodayWidgetProvider::class.java)
            .setAction(ACTION_TOGGLE_TODOS)
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun uiPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)

    private fun isNight(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    private fun dayKey(cal: Calendar): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)

    // ------------------------------------------------------------------ models

    private data class HabitItem(
        val id: String,
        val title: String,
        val done: Boolean,
        val colorDark: Int,
        val colorLight: Int
    )

    private data class HabitsSnapshot(
        val day: String,
        val done: Int,
        val total: Int,
        val streak: Int,
        val habits: List<HabitItem>
    ) {
        companion object {
            fun parse(raw: String?): HabitsSnapshot? {
                if (raw.isNullOrEmpty()) return null
                return try {
                    val json = JSONObject(raw)
                    val list = json.optJSONArray("habits")
                    val habits = (0 until (list?.length() ?: 0)).map { i ->
                        val h = list!!.getJSONObject(i)
                        HabitItem(
                            id = h.getString("id"),
                            title = h.optString("title"),
                            done = h.optBoolean("done"),
                            colorDark = h.optLong("colorDark", 0xFF06B6D4).toInt(),
                            colorLight = h.optLong("colorLight", 0xFF0891B2).toInt()
                        )
                    }
                    HabitsSnapshot(
                        day = json.optString("day"),
                        done = json.optInt("done"),
                        total = json.optInt("total"),
                        streak = json.optInt("streak"),
                        habits = habits
                    )
                } catch (e: Exception) {
                    null
                }
            }
        }
    }

    private data class TodoItem(val id: String, val title: String)

    private data class TodosSnapshot(val count: Int, val items: List<TodoItem>) {
        companion object {
            fun parse(raw: String?): TodosSnapshot {
                if (raw.isNullOrEmpty()) return TodosSnapshot(0, emptyList())
                return try {
                    val json = JSONObject(raw)
                    val list = json.optJSONArray("todos")
                    val items = (0 until (list?.length() ?: 0)).map { i ->
                        val t = list!!.getJSONObject(i)
                        TodoItem(t.getString("id"), t.optString("title"))
                    }
                    TodosSnapshot(json.optInt("count", items.size), items)
                } catch (e: Exception) {
                    TodosSnapshot(0, emptyList())
                }
            }
        }
    }

    private class HabitSlot(val row: Int, val dot: Int, val title: Int, val status: Int)
    private class TodoSlot(val row: Int, val title: Int)

    companion object {
        const val ACTION_TOGGLE_TODOS = "com.sayantan.habitloop.widget.TOGGLE_TODOS"

        private const val KEY_HABITS = "habits_snapshot"
        private const val KEY_TODOS = "todos_snapshot"
        private const val KEY_ENABLED = "widget_enabled"
        private const val UI_PREFS = "habit_today_widget_ui"
        private const val KEY_TODOS_EXPANDED = "todos_expanded"

        private const val RING_DP = 48

        // Vertical space in dp, matching widget_today.xml: padding (28) +
        // header (56) + divider block (13) + to-do header (32).
        private const val FIXED_CHROME_DP = 129
        private const val HABITS_MARGIN_DP = 8
        private const val HABIT_ROW_DP = 34 // 30 row + 4 margin
        private const val TODO_ROW_DP = 28

        private val HABIT_SLOTS = listOf(
            HabitSlot(R.id.habit_row_0, R.id.habit_dot_0, R.id.habit_title_0, R.id.habit_status_0),
            HabitSlot(R.id.habit_row_1, R.id.habit_dot_1, R.id.habit_title_1, R.id.habit_status_1),
            HabitSlot(R.id.habit_row_2, R.id.habit_dot_2, R.id.habit_title_2, R.id.habit_status_2),
            HabitSlot(R.id.habit_row_3, R.id.habit_dot_3, R.id.habit_title_3, R.id.habit_status_3),
        )

        private val TODO_SLOTS = listOf(
            TodoSlot(R.id.todo_row_0, R.id.todo_title_0),
            TodoSlot(R.id.todo_row_1, R.id.todo_title_1),
            TodoSlot(R.id.todo_row_2, R.id.todo_title_2),
        )
    }
}
