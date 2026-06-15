# -*- coding: utf-8 -*-
from __future__ import print_function
import Tkinter as tk
import ttk
import tkMessageBox
import json
import os
import subprocess
import threading
import sys
import re
import time
import urllib2
import urllib
import ssl
import locale

if sys.version_info[0] < 3:
    reload(sys)
    sys.setdefaultencoding('utf-8')

CONFIG_FILE = os.path.expanduser("~/.itunes_genius_ai.json")

def get_sys_lang():
    try:
        loc = locale.getdefaultlocale()[0]
        if loc:
            if loc.startswith('ru'): return 'ru'
            if loc.startswith('be'): return 'be'
            if loc.startswith('ko'): return 'ko'
            if loc.startswith('ja'): return 'ja'
            if loc.startswith('zh'): return 'zh'
            if loc.startswith('de'): return 'de'
            if loc.startswith('pl'): return 'pl'
            if loc.startswith('et'): return 'et'
            if loc.startswith('es'): return 'es'
    except: pass
    return 'en'

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                cfg = json.load(f)
                if "lang" not in cfg: cfg["lang"] = get_sys_lang()
                return cfg
        except: pass
    return {"provider": "Gemini", "api_key": "", "model": "google/gemini-2.0-flash-exp:free", "lang": get_sys_lang()}

CONFIG_DATA = load_config()

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f)

# --- ЛОКАЛИЗАЦИЯ (i18n) ---
LANGUAGES = {
    "en": {
        "ssl_update_msg": "Your Mac uses an outdated security certificate (OpenSSL 0.9.8).\n\nTo ensure stable and fast AI connections, we strongly recommend installing the official Python 2.7.18 update for macOS 10.9+.\n\nWould you like to download it now?",
        "setup_grp_lib": "iTunes Library",
        "btn_sync_lib": "SYNC LIBRARY",
        "msg_lib_synced": "Library cache updated!",
        "btn_sync": "SYNC MODELS",
        "sync_success": "Models updated successfully!",
        "sync_failed": "Failed to sync models. Please check your internet connection.",
        "setup_grp_provider": "AI Provider",
        "setup_grp_conn": "Connection Settings",
        "setup_grp_prefs": "Preferences",
        "setup_log_pref": "Prompt to save text logs for errors and successful generation",
        "menu_settings": "Settings",
        "menu_ai_settings": "AI Settings...",
        "menu_language": "Language",
        "menu_quit": "Quit",
        "setup_title": "AI PROVIDER SETUP",
        "setup_provider": "Select Free AI Provider",
        "setup_model": "SELECT MODEL:",
        "setup_key": "ENTER API KEY:",
        "setup_btn": "VALIDATE & SAVE KEY",
        "status_checking": "Checking connection...",
        "status_success": "Success! Welcome.",
        "status_failed": "Validation failed.",
        "err_no_key": "Please enter an API key.",
        "err_conn": "Could not connect to the AI Provider.",
        "err_invalid_key": "Invalid API Key. Please check if it was copied completely.",
        "err_invalid_model": "Invalid Model ID. This model might be unavailable. Try selecting another one.",
        "err_429": "Error 429: Too Many Requests. The provider's free tier is currently overloaded. Please try another model.",
        "ask_save_log": "Do you want to save a detailed error log to your Desktop for debugging?",
        "log_saved_title": "Saved",
        "log_saved_msg": u"Log saved to Desktop as '{}'.",
        "restart_required": "Please restart the application to apply the selected language.",
        "help_title": "Help / Instructions",
        "help_text": "HOW TO GET AN API KEY:\n\nGemini (Google):\n1. Go to aistudio.google.com\n2. Click 'Get API key' -> 'Create API key'.\n\nGroq:\n1. Go to console.groq.com\n2. Click 'API Keys' -> 'Create API Key'.\n\nOpenRouter (BEST FOR BYPASSING GEO-BLOCKS):\n1. Go to openrouter.ai\n2. Click 'Keys' -> 'Create Key'.\nOpenRouter provides access to FREE models from Google and Meta, even if they are blocked in your country.\n\nNote: The model list updates automatically from the web. You can also manually type a new model name in the dropdown.",
        "main_title": "iGeniusAI",
        "pl_name": "What should your playlist be named:",
        "pl_mood": "What kind of music would you like to see in the playlist?",
        "pl_count": "How many songs should be in the playlist? (Available max: {}):",
        "def_name": "Playlist",
        "btn_gen": "GENERATE PLAYLIST",
        "footer": u"© 2026 iTunesGeniusAI | Note: AI models are not perfect.\nFor better results, try different models in Settings.",
        "err_fill_all": "Please fill in all fields.",
        "prog_title": "Processing...",
        "prog_start": "Starting...",
        "prog_stop": "Force Stop",
        "prog_canceling": "Canceling...",
        "prog_read": "Reading iTunes Library... ({}/{})",
        "prog_ask": "Asking AI Assistant...",
        "prog_create": "Creating playlist in iTunes...",
        "err_empty_lib": "iTunes Library is empty or could not be read. Cannot generate playlist.",
        "err_parse": "Error: The AI returned an invalid format instead of a playlist.",
        "err_unexp": "An unexpected error occurred during generation.",
        "msg_success": "Playlist '{}' has been created with {} tracks!",
        "ask_success_log": "Would you like to save the process logs (including the AI's raw response) to your Desktop for analysis?"
    },
    "ru": {
        "ssl_update_msg": u"Ваш Mac использует устаревшие сертификаты безопасности (OpenSSL 0.9.8).\n\nДля стабильной и быстрой работы с ИИ мы настоятельно рекомендуем установить официальное обновление Python 2.7.18 для macOS 10.9+.\n\nХотите скачать его сейчас?",
        "setup_grp_lib": u"Медиатека iTunes",
        "btn_sync_lib": u"СИНХРОНИЗИРОВАТЬ",
        "msg_lib_synced": u"Кэш библиотеки обновлён!",
        "btn_sync": u"СИНХРОНИЗИРОВАТЬ",
        "sync_success": u"Список моделей успешно обновлен!",
        "sync_failed": u"Ошибка синхронизации моделей.",
        "setup_grp_provider": u"ИИ Провайдер",
        "setup_grp_conn": u"Настройки подключения",
        "setup_grp_prefs": u"Настройки приложения",
        "setup_log_pref": u"Предлагать сохранение текстовых логов при ошибках и успехах",
        "menu_settings": u"Настройки",
        "menu_ai_settings": u"Настройки ИИ...",
        "menu_language": u"Язык",
        "menu_quit": u"Выйти",
        "setup_title": u"НАСТРОЙКА ИИ ПРОВАЙДЕРА",
        "setup_provider": u"Выберите бесплатного ИИ",
        "setup_model": u"ВЫБЕРИТЕ МОДЕЛЬ:",
        "setup_key": u"ВВЕДИТЕ API КЛЮЧ:",
        "setup_btn": u"ПРОВЕРИТЬ И СОХРАНИТЬ",
        "status_checking": u"Проверка подключения...",
        "status_success": u"Успешно! Добро пожаловать.",
        "status_failed": u"Ошибка проверки.",
        "err_no_key": u"Пожалуйста, введите API ключ.",
        "err_conn": u"Не удалось подключиться к ИИ Провайдеру.",
        "err_invalid_key": u"Неверный API Ключ. Проверьте, полностью ли он скопирован.",
        "err_invalid_model": u"Неверный ID модели. Возможно, она недоступна. Выберите другую.",
        "err_429": u"Ошибка 429: Слишком много запросов. Бесплатная модель перегружена. Попробуйте другую.",
        "ask_save_log": u"Хотите сохранить подробный лог ошибки на Рабочий стол для решения проблемы?",
        "log_saved_title": u"Сохранено",
        "log_saved_msg": u"Лог сохранен на Рабочий стол как '{}'.",
        "restart_required": u"Для применения выбранного языка выполните перезапуск приложения.",
        "help_title": u"Помощь / Инструкция",
        "help_text": u"КАК ПОЛУЧИТЬ API КЛЮЧ:\n\nGemini (Google):\n1. Зайдите на aistudio.google.com\n2. Нажмите 'Get API key' -> 'Create API key'.\n\nGroq:\n1. Зайдите на console.groq.com\n2. Нажмите 'API Keys' -> 'Create API Key'.\n\nOpenRouter (ЛУЧШИЙ ДЛЯ ОБХОДА БЛОКИРОВОК):\n1. Зайдите на openrouter.ai\n2. Нажмите 'Keys' -> 'Create Key'.\nOpenRouter дает доступ к БЕСПЛАТНЫМ моделям Google и Meta, даже если они заблокированы в вашей стране.\n\nПримечание: Список моделей обновляется автоматически. Вы также можете вручную вписать название модели.",
        "main_title": u"iGeniusAI",
        "pl_name": u"Как будет называться ваш плейлист:",
        "pl_mood": u"Какую музыку вы бы хотели видеть в плейлисте?",
        "pl_count": u"Какое количество песен должно быть? (доступный максимум: {}):",
        "def_name": u"Playlist",
        "btn_gen": u"СГЕНЕРИРОВАТЬ ПЛЕЙЛИСТ",
        "footer": u"© 2026 iTunesGeniusAI | Внимание: ИИ модели не идеальны.\nДля лучшего результата попробуйте выбрать другие доступные модели в настройках.",
        "err_fill_all": u"Пожалуйста, заполните все поля.",
        "prog_title": u"Обработка...",
        "prog_start": u"Запуск...",
        "prog_stop": u"Принудительная остановка",
        "prog_canceling": u"Остановка...",
        "prog_read": u"Чтение медиатеки iTunes... ({}/{})",
        "prog_ask": u"Запрос к ИИ ассистенту...",
        "prog_create": u"Создание плейлиста в iTunes...",
        "err_empty_lib": u"Медиатека iTunes пуста или недоступна. Невозможно создать плейлист.",
        "err_parse": u"Ошибка: ИИ вернул неверный формат ответа вместо плейлиста.",
        "err_unexp": u"Произошла непредвиденная ошибка во время генерации.",
        "msg_success": u"Плейлист '{}' был успешно создан! Добавлено треков: {}",
        "ask_success_log": u"Хотите сохранить логи процесса (включая сырой ответ ИИ) на Рабочий стол для анализа?"
    },
    "be": {
        "ssl_update_msg": u"Ваш Mac выкарыстоўвае састарэлыя сертыфікаты бяспекі (OpenSSL 0.9.8).\n\nДля стабільнай і хуткай працы з ШІ мы настойліва рэкамендуем усталяваць афіцыйнае абнаўленне Python 2.7.18 для macOS 10.9+.\n\nХочаце спампаваць яго зараз?",
        "setup_grp_lib": u"Медыятэка iTunes",
        "btn_sync_lib": u"СІНХРАНІЗАВАЦЬ",
        "msg_lib_synced": u"Кэш бібліятэкі абноўлены!",
        "btn_sync": u"СІНХРАНІЗАВАЦЬ",
        "sync_success": u"Спіс мадэляў паспяхова абноўлены!",
        "sync_failed": u"Памылка сінхранізацыі мадэляў.",
        "setup_grp_provider": u"ШІ Правайдэр",
        "setup_grp_conn": u"Налады падключэння",
        "setup_grp_prefs": u"Налады праграмы",
        "setup_log_pref": u"Прапаноўваць захаванне тэкставых логаў пры памылках і поспехах",
        "menu_settings": u"Налады",
        "menu_ai_settings": u"Налады ШІ...",
        "menu_language": u"Мова",
        "menu_quit": u"Выйсці",
        "setup_title": u"НАЛАДА ШІ ПРАВАЙДЭРА",
        "setup_provider": u"Выберыце бясплатнага ШІ",
        "setup_model": u"ВЫБЕРЫЦЕ МАДЭЛЬ:",
        "setup_key": u"УВЯДЗІЦЕ API КЛЮЧ:",
        "setup_btn": u"ПРАВЕРЫЦЬ І ЗАХАВАЦЬ",
        "status_checking": u"Праверка падключэння...",
        "status_success": u"Паспяхова! Сардэчна запрашаем.",
        "status_failed": u"Памылка праверкі.",
        "err_no_key": u"Калі ласка, увядзіце API ключ.",
        "err_conn": u"Не ўдалося падключыцца да ШІ Правайдэра.",
        "err_invalid_key": u"Няправільны API Ключ. Праверце, ці поўнасцю ён скапіяваны.",
        "err_invalid_model": u"Няправільны ID мадэлі. Магчыма, яна недаступная. Выберыце іншую.",
        "err_429": u"Памылка 429: Занадта шмат запытаў. Бясплатная мадэль перагружана. Паспрабуйце іншую.",
        "ask_save_log": u"Хочаце захаваць падрабязны лог памылкі на Працоўны стол для вырашэння праблемы?",
        "log_saved_title": u"Захавана",
        "log_saved_msg": u"Лог захаваны на Працоўны стол як '{}'.",
        "restart_required": u"Для прымянення абранай мовы выканайце перазапуск праграмы.",
        "help_title": u"Дапамога / Інструкцыя",
        "help_text": u"ЯК АТРЫМАЦЬ API КЛЮЧ:\n\nGemini (Google):\n1. Зайдзіце на aistudio.google.com\n2. Націсніце 'Get API key' -> 'Create API key'.\n\nGroq:\n1. Зайдзіце на console.groq.com\n2. Націсніце 'API Keys' -> 'Create API Key'.\n\nOpenRouter (ЛЕПШЫ ДЛЯ АБХОДУ БЛАКІРОВАК):\n1. Зайдзіце на openrouter.ai\n2. Націсніце 'Keys' -> 'Create Key'.\nOpenRouter дае доступ да БЯСПЛАТНЫХ мадэляў Google і Meta, нават калі яны заблакаваныя ў вашай краіне.\n\nЗаўвага: Спіс мадэляў абнаўляецца аўтаматычна. Вы таксама можаце ўручную ўпісаць назву мадэлі.",
        "main_title": "iGeniusAI",
        "pl_name": u"Як будзе называцца ваш плэйліст:",
        "pl_mood": u"Якую музыку вы хацелі б бачыць у плэйлісце?",
        "pl_count": u"Якая колькасць песень павінна быць? (даступны максімум: {}):",
        "def_name": "Playlist",
        "btn_gen": u"ЗГЕНЕРАВАЦЬ ПЛЭЙЛІСТ",
        "footer": u"© 2026 iTunesGeniusAI | Увага: ШІ мадэлі не ідэальныя.\nДля лепшага выніку паспрабуйце выбраць іншыя даступныя мадэлі ў наладах.",
        "err_fill_all": u"Калі ласка, запоўніце ўсе палі.",
        "prog_title": u"Апрацоўка...",
        "prog_start": u"Запуск...",
        "prog_stop": u"Прымусовы прыпынак",
        "prog_canceling": u"Прыпыненне...",
        "prog_read": u"Чытанне медыятэкі iTunes... ({}/{})",
        "prog_ask": u"Запыт да ШІ асістэнта...",
        "prog_create": u"Стварэнне плэйліста ў iTunes...",
        "err_empty_lib": u"Медыятэка iTunes пустая або недаступная. Немагчыма стварыць плэйліст.",
        "err_parse": u"Памылка: ШІ вярнуў няправільны фармат адказу замест плэйліста.",
        "err_unexp": u"Адбылася непрадбачаная памылка падчас генерацыі.",
        "msg_success": u"Плэйліст '{}' быў паспяхова створаны! Дададзена трэкаў: {",
        "ask_success_log": u"Хочаце захаваць логі працэсу (уключаючы сыры адказ ШІ) на Працоўны стол для аналізу?"
    },
    "ko": {
        "ssl_update_msg": u"Mac의 보안 인증서가 오래되었습니다(OpenSSL 0.9.8).\n\n안정적인 연결을 위해 macOS 10.9+용 공식 Python 2.7.18 업데이트를 설치하는 것이 좋습니다.\n\n지금 다운로드하시겠습니까?",
        "setup_grp_lib": u"iTunes 보관함",
        "btn_sync_lib": u"보관함 동기화",
        "msg_lib_synced": u"보관함 캐시가 업데이트되었습니다!",
        "btn_sync": u"모델 동기화",
        "sync_success": u"모델이 성공적으로 업데이트되었습니다!",
        "sync_failed": u"모델 동기화에 실패했습니다.",
        "setup_grp_provider": u"AI 제공자",
        "setup_grp_conn": u"연결 설정",
        "setup_grp_prefs": u"환경 설정",
        "setup_log_pref": u"오류 및 성공적인 생성 시 텍스트 로그 저장 여부 묻기",
        "menu_settings": u"설정",
        "menu_ai_settings": u"AI 설정...",
        "menu_language": u"언어",
        "menu_quit": u"종료",
        "setup_title": u"AI 제공자 설정",
        "setup_provider": u"무료 AI 제공자 선택",
        "setup_model": u"모델 선택:",
        "setup_key": u"API 키 입력:",
        "setup_btn": u"확인 및 저장",
        "status_checking": u"연결 확인 중...",
        "status_success": u"성공! 환영합니다.",
        "status_failed": u"확인 실패.",
        "err_no_key": u"API 키를 입력하세요.",
        "err_conn": u"AI 제공자에 연결할 수 없습니다.",
        "err_invalid_key": u"유효하지 않은 API 키입니다. 완전히 복사되었는지 확인하세요.",
        "err_invalid_model": u"유효하지 않은 모델 ID입니다. 다른 모델을 선택해 보세요.",
        "err_429": u"에러 429: 요청이 너무 많습니다. 무료 계층이 과부하 상태입니다.",
        "ask_save_log": u"디버깅을 위해 상세한 에러 로그를 바탕화면에 저장하시겠습니까?",
        "log_saved_title": u"저장됨",
        "log_saved_msg": u"로그가 바탕화면에 '{}\'로 저장되었습니다.",
        "restart_required": u"선택한 언어를 적용하려면 응용 프로그램을 다시 시작하십시오.",
        "help_title": u"도움말 / 안내",
        "help_text": u"API 키 얻는 방법:\n\nGemini (Google):\n1. aistudio.google.com으로 이동\n2. 'Get API key' -> 'Create API key' 클릭.\n\nGroq:\n1. console.groq.com으로 이동\n2. 'API Keys' -> 'Create API Key' 클릭.\n\nOpenRouter (지역 차단 우회에 최고):\n1. openrouter.ai로 이동\n2. 'Keys' -> 'Create Key' 클릭.\n\n참고: 모델 목록은 자동으로 업데이트됩니다. 모델 이름을 직접 입력할 수도 있습니다.",
        "main_title": "iGeniusAI",
        "pl_name": u"플레이리스트의 이름:",
        "pl_mood": u"어떤 종류의 음악을 원하시나요?",
        "pl_count": u"몇 곡을 넣을까요? (사용 가능한 최대: {}):",
        "def_name": "Playlist",
        "btn_gen": u"플레이리스트 생성",
        "footer": u"© 2026 iTunesGeniusAI | 참고: AI 모델은 완벽하지 않습니다.\n더 나은 결과를 위해 설정에서 다른 모델을 사용해 보세요.",
        "err_fill_all": u"모든 필드를 입력하세요.",
        "prog_title": u"처리 중...",
        "prog_start": u"시작 중...",
        "prog_stop": u"강제 중지",
        "prog_canceling": u"취소 중...",
        "prog_read": u"iTunes 보관함 읽는 중... ({}/{})",
        "prog_ask": u"AI 어시스턴트에게 묻는 중...",
        "prog_create": u"iTunes에 플레이리스트 생성 중...",
        "err_empty_lib": u"iTunes 보관함이 비어 있거나 읽을 수 없습니다.",
        "err_parse": u"에러: AI가 잘못된 형식을 반환했습니다.",
        "err_unexp": u"생성 중 예상치 못한 오류가 발생했습니다.",
        "msg_success": u"플레이리스트 '{}'이(가) 성공적으로 생성되었습니다! {}곡 추가됨.",
        "ask_success_log": u"분석을 위해 프로세스 로그를 바탕화면에 저장하시겠습니까?"
    },
    "ja": {
        "ssl_update_msg": u"お使いのMacのセキュリティ証明書は古くなっています(OpenSSL 0.9.8)。\n\n安定した接続のために、macOS 10.9以降向けの公式Python 2.7.18アップデートをインストールすることを強くお勧めします。\n\n今すぐダウンロードしますか？",
        "setup_grp_lib": u"iTunesライブラリ",
        "btn_sync_lib": u"ライブラリを同期",
        "msg_lib_synced": u"ライブラリのキャッシュが更新されました！",
        "btn_sync": u"モデルを同期",
        "sync_success": u"モデルが正常に更新されました！",
        "sync_failed": u"モデルの同期に失敗しました。",
        "setup_grp_provider": u"AIプロバイダー",
        "setup_grp_conn": u"接続設定",
        "setup_grp_prefs": u"環境設定",
        "setup_log_pref": u"エラーおよび成功時のテキストログの保存を確認する",
        "menu_settings": u"設定",
        "menu_ai_settings": u"AI設定...",
        "menu_language": u"言語",
        "menu_quit": u"終了",
        "setup_title": u"AIプロバイダー設定",
        "setup_provider": u"無料のAIプロバイダーを選択",
        "setup_model": u"モデルを選択:",
        "setup_key": u"APIキーを入力:",
        "setup_btn": u"検証して保存",
        "status_checking": u"接続を確認中...",
        "status_success": u"成功しました！ようこそ。",
        "status_failed": u"検証に失敗しました。",
        "err_no_key": u"APIキーを入力してください。",
        "err_conn": u"AIプロバイダーに接続できませんでした。",
        "err_invalid_key": u"無効なAPIキーです。完全にコピーされているか確認してください。",
        "err_invalid_model": u"無効なモデルIDです。他のモデルを選択してください。",
        "err_429": u"エラー429: リクエストが多すぎます。プロバイダーが混雑しています。",
        "ask_save_log": u"詳細なエラーログをデスクトップに保存しますか？",
        "log_saved_title": u"保存完了",
        "log_saved_msg": u"ログがデスクトップに「{}\'。",
        "restart_required": u"選択した言語を適用するには、アプリケーションを再起動してください。",
        "help_title": u"ヘルプ / 手順",
        "help_text": u"APIキーの取得方法:\n\nGemini (Google):\n1. aistudio.google.comにアクセス\n2. 'Get API key' -> 'Create API key' をクリック。\n\nGroq:\n1. console.groq.comにアクセス\n2. 'API Keys' -> 'Create API Key' をクリック。\n\nOpenRouter (地域ブロックの回避に最適):\n1. openrouter.aiにアクセス\n2. 'Keys' -> 'Create Key' をクリック。\n\n注意: モデルリストは自動的に更新されます。モデル名を手動で入力することも可能です。",
        "main_title": "iGeniusAI",
        "pl_name": u"プレイリストの名前:",
        "pl_mood": u"プレイリストに入れたい音楽の雰囲気は？",
        "pl_count": u"曲数はいくつにしますか？ (利用可能な最大数: {}):",
        "def_name": "Playlist",
        "btn_gen": u"プレイリストを生成",
        "footer": u"© 2026 iTunesGeniusAI | 注意: AIは完璧ではありません。\nより良い結果を得るには設定で異なるモデルを試してください。",
        "err_fill_all": u"すべての項目を入力してください。",
        "prog_title": u"処理中...",
        "prog_start": u"開始中...",
        "prog_stop": u"強制停止",
        "prog_canceling": u"キャンセル中...",
        "prog_read": u"iTunesライブラリを読み込み中... ({}/{})",
        "prog_ask": u"AIアシスタントに質問中...",
        "prog_create": u"iTunesでプレイリストを作成中...",
        "err_empty_lib": u"ライブラリが空か、読み込めませんでした。",
        "err_parse": u"エラー: AIがプレイリストではなく無効な形式を返しました。",
        "err_unexp": u"生成中に予期しないエラーが発生しました。",
        "msg_success": u"プレイリスト「{}」が作成されました！{}曲が追加されました。",
        "ask_success_log": u"AIの生の応答を含むプロセスログを保存しますか？"
    },
    "zh": {
        "ssl_update_msg": u"您的 Mac 正在使用过时的安全证书 (OpenSSL 0.9.8)。\n\n为了确保稳定和快速的 AI 连接，我们强烈建议安装适用于 macOS 10.9+ 的官方 Python 2.7.18 更新。\n\n您现在要下载吗？",
        "setup_grp_lib": u"iTunes 资料库",
        "btn_sync_lib": u"同步资料库",
        "msg_lib_synced": u"资料库缓存已更新！",
        "btn_sync": u"同步模型",
        "sync_success": u"模型更新成功！",
        "sync_failed": u"同步模型失败。",
        "setup_grp_provider": u"AI 提供商",
        "setup_grp_conn": u"连接设置",
        "setup_grp_prefs": u"偏好设置",
        "setup_log_pref": u"询问是否保存详细的文本日志",
        "menu_settings": u"设置",
        "menu_ai_settings": u"AI设置...",
        "menu_language": u"语言",
        "menu_quit": u"退出",
        "setup_title": u"AI提供商设置",
        "setup_provider": u"选择免费的AI提供商",
        "setup_model": u"选择模型：",
        "setup_key": u"输入API密钥：",
        "setup_btn": u"验证并保存",
        "status_checking": u"正在检查连接...",
        "status_success": u"成功！欢迎使用。",
        "status_failed": u"验证失败。",
        "err_no_key": u"请输入API密钥。",
        "err_conn": u"无法连接到AI提供商。",
        "err_invalid_key": u"无效的API密钥。请检查是否已完整复制。",
        "err_invalid_model": u"无效的模型ID。尝试选择另一个。",
        "err_429": u"错误 429：请求过多。免费层目前已超载。",
        "ask_save_log": u"您想将详细的错误日志保存到桌面进行调试吗？",
        "log_saved_title": u"已保存",
        "log_saved_msg": u"日志已保存到桌面为 '{}',",
        "restart_required": u"请重新启动应用程序以应用所选语言。",
        "help_title": u"帮助 / 说明",
        "help_text": u"如何获取API密钥：\n\nGemini (Google)：\n1. 访问 aistudio.google.com\n2. 点击 'Get API key' -> 'Create API key'。\n\nGroq：\n1. 访问 console.groq.com\n2. 点击 'API Keys' -> 'Create API Key'。\n\nOpenRouter（最适合绕过地理限制）：\n1. 访问 openrouter.ai\n2. 点击 'Keys' -> 'Create Key'。\n\n注意：模型列表会自动更新。您也可以手动输入模型名称。",
        "main_title": "iGeniusAI",
        "pl_name": u"您的播放列表名称：",
        "pl_mood": u"您想在播放列表中听到什么样的音乐？",
        "pl_count": u"播放列表中应该有多少首歌？（可用最大数量：{}）：",
        "def_name": "Playlist",
        "btn_gen": u"生成播放列表",
        "footer": u"© 2026 iTunesGeniusAI | 注意：AI模型并不完美。\n为了获得更好的结果，请在设置中尝试不同的模型。",
        "err_fill_all": u"请填写所有字段。",
        "prog_title": u"正在处理...",
        "prog_start": u"正在启动...",
        "prog_stop": u"强制停止",
        "prog_canceling": u"正在取消...",
        "prog_read": u"正在读取iTunes资料库... ({}/{})",
        "prog_ask": u"正在询问AI助手...",
        "prog_create": u"正在iTunes中创建播放列表...",
        "err_empty_lib": u"iTunes资料库为空或无法读取。",
        "err_parse": u"错误：AI返回了无效的格式。",
        "err_unexp": u"生成过程中发生意外错误。",
        "msg_success": u"播放列表 '{}' 已成功创建！添加了 {} 首曲目。",
        "ask_success_log": u"您想将处理日志保存到桌面进行分析吗？"
    },
    "de": {
        "ssl_update_msg": u"Ihr Mac verwendet veraltete Sicherheitszertifikate (OpenSSL 0.9.8).\n\nFür stabile Verbindungen empfehlen wir die Installation des offiziellen Python 2.7.18-Updates für macOS 10.9+.\n\nMöchten Sie es jetzt herunterladen?",
        "setup_grp_lib": u"iTunes-Mediathek",
        "btn_sync_lib": u"MEDIATHEK SYNC",
        "msg_lib_synced": u"Mediathek-Cache aktualisiert!",
        "btn_sync": u"MODELLE SYNC",
        "sync_success": u"Modelle erfolgreich aktualisiert!",
        "sync_failed": u"Fehler beim Synchronisieren der Modelle.",
        "setup_grp_provider": u"KI-Anbieter",
        "setup_grp_conn": u"Verbindungseinstellungen",
        "setup_grp_prefs": u"Einstellungen",
        "setup_log_pref": u"Vor dem Speichern von Protokollen fragen",
        "menu_settings": u"Einstellungen",
        "menu_ai_settings": u"KI-Einstellungen...",
        "menu_language": u"Sprache",
        "menu_quit": u"Beenden",
        "setup_title": u"KI-ANBIETER SETUP",
        "setup_provider": u"Kostenlosen KI-Anbieter wählen",
        "setup_model": u"MODELL WÄHLEN:",
        "setup_key": u"API-SCHLÜSSEL EINGEBEN:",
        "setup_btn": u"PRÜFEN & SPEICHERN",
        "status_checking": u"Verbindung wird geprüft...",
        "status_success": u"Erfolgreich! Willkommen.",
        "status_failed": u"Überprüfung fehlgeschlagen.",
        "err_no_key": u"Bitte geben Sie einen API-Schlüssel ein.",
        "err_conn": u"Keine Verbindung zum KI-Anbieter möglich.",
        "err_invalid_key": u"Ungültiger API-Schlüssel. Bitte prüfen Sie die Eingabe.",
        "err_invalid_model": u"Ungültige Modell-ID. Bitte wählen Sie ein anderes Modell.",
        "err_429": u"Fehler 429: Zu viele Anfragen. Der Anbieter ist überlastet.",
        "ask_save_log": u"Möchten Sie ein Fehlerprotokoll auf Ihrem Schreibtisch speichern?",
        "log_saved_title": u"Gespeichert",
        "log_saved_msg": u"Protokoll als '{}\' gespeichert.",
        "restart_required": u"Bitte starten Sie die Anwendung neu, um die ausgewählte Sprache anzuwenden.",
        "help_title": u"Hilfe / Anleitung",
        "help_text": u"API-SCHLÜSSEL ERHALTEN:\n\nGemini (Google):\n1. Gehe zu aistudio.google.com\n2. Klicke auf 'Get API key' -> 'Create API key'.\n\nGroq:\n1. Gehe zu console.groq.com\n2. Klicke auf 'API Keys' -> 'Create API Key'.\n\nOpenRouter:\n1. Gehe zu openrouter.ai\n2. Klicke auf 'Keys' -> 'Create Key'.\n\nHinweis: Die Modellliste wird automatisch aktualisiert.",
        "main_title": "iGeniusAI",
        "pl_name": u"Wie soll Ihre Playlist heißen:",
        "pl_mood": u"Welche Art von Musik möchten Sie in der Playlist sehen?",
        "pl_count": u"Wie viele Songs sollen in der Playlist sein? (Maximum: {}):",
        "def_name": "Playlist",
        "btn_gen": u"PLAYLIST GENERIEREN",
        "footer": u"© 2026 iTunesGeniusAI | Hinweis: KI-Modelle sind nicht perfekt.\nProbieren Sie andere Modelle in den Einstellungen aus.",
        "err_fill_all": u"Bitte füllen Sie alle Felder aus.",
        "prog_title": u"Verarbeitung...",
        "prog_start": u"Starten...",
        "prog_stop": u"Stopp erzwingen",
        "prog_canceling": u"Abbrechen...",
        "prog_read": u"iTunes-Mediathek wird gelesen... ({}/{})",
        "prog_ask": u"KI-Assistent wird gefragt...",
        "prog_create": u"Playlist wird erstellt...",
        "err_empty_lib": u"Die iTunes-Mediathek ist leer oder unlesbar.",
        "err_parse": u"Fehler: Die KI hat ein ungültiges Format zurückgegeben.",
        "err_unexp": u"Ein unerwarteter Fehler ist aufgetreten.",
        "msg_success": u"Playlist '{}' erfolgreich erstellt! {} Titel hinzugefügt.",
        "ask_success_log": u"Möchten Sie die Protokolle speichern?"
    },
    "pl": {
        "ssl_update_msg": u"Twój Mac używa przestarzałych certyfikatów bezpieczeństwa (OpenSSL 0.9.8).\n\nAby zapewnić stabilne połączenia, zdecydowanie zalecamy zainstalowanie oficjalnej aktualizacji Python 2.7.18 dla systemu macOS 10.9+.\n\nCzy chcesz pobrać ją teraz?",
        "setup_grp_lib": u"Biblioteka iTunes",
        "btn_sync_lib": u"SYNCHRONIZUJ",
        "msg_lib_synced": u"Pamięć podręczna biblioteki zaktualizowana!",
        "btn_sync": u"SYNCHRONIZUJ",
        "sync_success": u"Modele zaktualizowane pomyślnie!",
        "sync_failed": u"Nie udało się zsynchronizować modeli.",
        "setup_grp_provider": u"Dostawca AI",
        "setup_grp_conn": u"Ustawienia połączenia",
        "setup_grp_prefs": u"Preferencje",
        "setup_log_pref": u"Pytaj o zapisywanie dzienników tekstowych",
        "menu_settings": u"Ustawienia",
        "menu_ai_settings": u"Ustawienia AI...",
        "menu_language": u"Język",
        "menu_quit": u"Zakończ",
        "setup_title": u"KONFIGURACJA AI",
        "setup_provider": u"Wybierz dostawcę AI",
        "setup_model": u"WYBIERZ MODEL:",
        "setup_key": u"WPROWADŹ KLUCZ API:",
        "setup_btn": u"SPRAWDŹ I ZAPISZ",
        "status_checking": u"Sprawdzanie połączenia...",
        "status_success": u"Sukces! Witamy.",
        "status_failed": u"Weryfikacja nie powiodła się.",
        "err_no_key": u"Proszę wprowadzić klucz API.",
        "err_conn": u"Nie udało się połączyć z dostawcą AI.",
        "err_invalid_key": u"Nieprawidłowy klucz API. Sprawdź, czy został skopiowany w całości.",
        "err_invalid_model": u"Nieprawidłowy ID modelu. Wybierz inny model.",
        "err_429": u"Błąd 429: Zbyt wiele zapytań. Serwery są przeciążone.",
        "ask_save_log": u"Czy chcesz zapisać dziennik błędów na pulpicie?",
        "log_saved_title": u"Zapisano",
        "log_saved_msg": u"Dziennik zapisany jako '{}'.",
        "restart_required": u"Uruchom ponownie aplikację, aby zastosować wybrany język.",
        "help_title": u"Pomoc",
        "help_text": u"JAK UZYSKAĆ KLUCZ API:\n\nGemini: aistudio.google.com\nGroq: console.groq.com\nOpenRouter: openrouter.ai\n\nLista modeli aktualizuje się automatycznie.",
        "main_title": "iGeniusAI",
        "pl_name": u"Jak powinna nazywać się Twoja playlista:",
        "pl_mood": u"Jaką muzykę chciałbyś usłyszeć na tej playliście?",
        "pl_count": u"Ile piosenek powinno się w niej znaleźć? (Maksimum: {}):",
        "def_name": "Playlist",
        "btn_gen": u"GENERUJ PLAYLISTĘ",
        "footer": u"© 2026 iTunesGeniusAI | Uwaga: Modele AI nie są idealne.\nAby uzyskać lepsze wyniki, wypróbuj różne modele w Ustawieniach.",
        "err_fill_all": u"Proszę wypełnić wszystkie pola.",
        "prog_title": u"Przetwarzanie...",
        "prog_start": u"Uruchamianie...",
        "prog_stop": u"Wymuś zatrzymanie",
        "prog_canceling": u"Anulowanie...",
        "prog_read": u"Odczytywanie biblioteki iTunes... ({}/{})",
        "prog_ask": u"Pytanie asystenta AI...",
        "prog_create": u"Tworzenie playlisty w iTunes...",
        "err_empty_lib": u"Biblioteka iTunes jest pusta lub nieczytelna.",
        "err_parse": u"Błąd: AI zwróciło nieprawidłowy format.",
        "err_unexp": u"Wystąpił nieoczekiwany błąd.",
        "msg_success": u"Playlista '{}' utworzona! Dodano {} utworów.",
        "ask_success_log": u"Czy chcesz zapisać logi procesu na pulpicie?"
    },
    "et": {
        "ssl_update_msg": u"Teie Mac kasutab aegunud turvasertifikaate (OpenSSL 0.9.8).\n\nStabiilsete ühenduste tagamiseks soovitame tungivalt installida ametlik Python 2.7.18 värskendus macOS 10.9+ jaoks.\n\nKas soovite selle kohe alla laadida?",
        "setup_grp_lib": u"iTunesi Raamatukogu",
        "btn_sync_lib": u"SÜNKROONI",
        "msg_lib_synced": u"Raamatukogu vahemälu uuendatud!",
        "btn_sync": u"SÜNKROONI",
        "sync_success": u"Mudelid edukalt uuendatud!",
        "sync_failed": u"Mudelite sünkroonimine ebaõnnestus.",
        "setup_grp_provider": u"AI Teenusepakkuja",
        "setup_grp_conn": u"Ühenduse seaded",
        "setup_grp_prefs": u"Eelistused",
        "setup_log_pref": u"Küsi tekstilogide salvestamise kohta",
        "menu_settings": u"Seaded",
        "menu_ai_settings": u"AI Seaded...",
        "menu_language": u"Keel",
        "menu_quit": u"Välju",
        "setup_title": u"AI SEADISTAMINE",
        "setup_provider": u"Vali tasuta AI",
        "setup_model": u"VALI MUDEL:",
        "setup_key": u"SISESTA API VÕTI:",
        "setup_btn": u"KONTROLLI JA SALVESTA",
        "status_checking": u"Ühenduse kontrollimine...",
        "status_success": u"Edukas! Tere tulemast.",
        "status_failed": u"Valideerimine ebaõnnestus.",
        "err_no_key": u"Palun sisesta API võti.",
        "err_conn": u"AI teenusepakkujaga ei õnnestunud ühendust luua.",
        "err_invalid_key": u"Vigane API võti. Palun kontrolli kopeerimist.",
        "err_invalid_model": u"Vigane mudeli ID. Vali teine mudel.",
        "err_429": u"Viga 429: Liiga palju päringuid. Serverid on ülekoormatud.",
        "ask_save_log": u"Kas soovid salvestada vealogifaili töölauale?",
        "log_saved_title": u"Salvestatud",
        "log_saved_msg": u"Logi salvestati nimega '{}'.",
        "restart_required": u"Valitud keele rakendamiseks taaskäivitage rakendus.",
        "help_title": u"Abi",
        "help_text": u"API VÕTMED:\nGemini: aistudio.google.com\nGroq: console.groq.com\nOpenRouter: openrouter.ai",
        "main_title": "iGeniusAI",
        "pl_name": u"Mis peaks olema sinu esitusloendi nimi:",
        "pl_mood": u"Millist muusikat soovid esitusloendis näha?",
        "pl_count": u"Mitu lugu peaks esitusloendis olema? (Maksimum: {}):",
        "def_name": "Playlist",
        "btn_gen": u"GENEREERI ESITUSLOEND",
        "footer": u"© 2026 iTunesGeniusAI | Märkus: AI mudelid pole täiuslikud.\nParemate tulemuste saamiseks proovi teisi mudeleid.",
        "err_fill_all": u"Palun täida kõik väljad.",
        "prog_title": u"Töötlemine...",
        "prog_start": u"Käivitamine...",
        "prog_stop": u"Sundpeata",
        "prog_canceling": u"Tühistamine...",
        "prog_read": u"iTunesi raamatukogu lugemine... ({}/{})",
        "prog_ask": u"AI assistendilt küsimine...",
        "prog_create": u"Esitusloendi loomine...",
        "err_empty_lib": u"iTunesi raamatukogu on tühi.",
        "err_parse": u"Viga: AI tagastas vigase vormingu.",
        "err_unexp": u"Ilmnes ootamatu viga.",
        "msg_success": u"Esitusloend '{}' on loodud! Lisati {} lugu.",
        "ask_success_log": u"Kas soovid salvestada logid töölauale?"
    },
    "es": {
        "ssl_update_msg": u"Su Mac utiliza certificados de seguridad obsoletos (OpenSSL 0.9.8).\n\nPara garantizar conexiones estables, recomendamos encarecidamente instalar la actualización oficial de Python 2.7.18 para macOS 10.9+.\n\n¿Desea descargarlo ahora?",
        "setup_grp_lib": u"Biblioteca de iTunes",
        "btn_sync_lib": u"SINCRONIZAR",
        "msg_lib_synced": u"¡Caché de biblioteca actualizado!",
        "btn_sync": u"SINCRONIZAR",
        "sync_success": u"¡Modelos actualizados con éxito!",
        "sync_failed": u"Error al sincronizar modelos.",
        "setup_grp_provider": u"Proveedor de IA",
        "setup_grp_conn": u"Ajustes de conexión",
        "setup_grp_prefs": u"Preferencias",
        "setup_log_pref": u"Preguntar si guardar registros de texto",
        "menu_settings": u"Ajustes",
        "menu_ai_settings": u"Ajustes de IA...",
        "menu_language": u"Idioma",
        "menu_quit": u"Salir",
        "setup_title": u"CONFIGURACIÓN DE IA",
        "setup_provider": u"Seleccione un Proveedor",
        "setup_model": u"SELECCIONE EL MODELO:",
        "setup_key": u"INGRESE LA CLAVE API:",
        "setup_btn": u"VALIDAR Y GUARDAR",
        "status_checking": u"Comprobando conexión...",
        "status_success": u"¡Éxito! Bienvenido.",
        "status_failed": u"Validación fallida.",
        "err_no_key": u"Por favor, introduzca una clave API.",
        "err_conn": u"No se pudo conectar al proveedor de IA.",
        "err_invalid_key": u"Clave API no válida. Compruebe si se copió completamente.",
        "err_invalid_model": u"ID de modelo no válido. Seleccione otro.",
        "err_429": u"Error 429: Demasiadas solicitudes. El servidor está sobrecargado.",
        "ask_save_log": u"¿Desea guardar un registro de errores en su Escritorio?",
        "log_saved_title": u"Guardado",
        "log_saved_msg": u"Registro guardado como '{}'.",
        "restart_required": u"Por favor, reinicie la aplicación para aplicar el idioma seleccionado.",
        "help_title": u"Ayuda",
        "help_text": u"CÓMO OBTENER UNA CLAVE API:\n\nGemini: aistudio.google.com\nGroq: console.groq.com\nOpenRouter: openrouter.ai\n\nNota: La lista de modelos se actualiza automáticamente.",
        "main_title": "iGeniusAI",
        "pl_name": u"Cómo debería llamarse tu lista de reproducción:",
        "pl_mood": u"¿Qué tipo de música te gustaría ver en la lista de reproducción?",
        "pl_count": u"¿Cuántas canciones debería haber? (Máximo: {}):",
        "def_name": "Playlist",
        "btn_gen": u"GENERAR LISTA",
        "footer": u"© 2026 iTunesGeniusAI | Nota: Los modelos de IA no son perfectos.\nPruebe diferentes modelos en los Ajustes.",
        "err_fill_all": u"Por favor, rellene todos los campos.",
        "prog_title": u"Procesando...",
        "prog_start": u"Iniciando...",
        "prog_stop": u"Forzar detención",
        "prog_canceling": u"Cancelando...",
        "prog_read": u"Leyendo la biblioteca de iTunes... ({}/{})",
        "prog_ask": u"Preguntando al asistente de IA...",
        "prog_create": u"Creando lista de reproducción...",
        "err_empty_lib": u"La biblioteca de iTunes está vacía o no se pudo leer.",
        "err_parse": u"Error: La IA devolvió un formato no válido.",
        "err_unexp": u"Ocurrió un error inesperado.",
        "msg_success": u"¡La lista '{}' se creó con éxito! Se añadieron {} pistas.",
        "ask_success_log": u"¿Desea guardar los registros del proceso para su análisis?"
    }
}

def _(key, *args):
    lang = CONFIG_DATA.get("lang", "en")
    text = LANGUAGES.get(lang, LANGUAGES["en"]).get(key, key)
    if args:
        return text.format(*args)
    return text

def run_as(s):
    p = subprocess.Popen(['osascript', '-e', s], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.communicate()[0].decode('utf-8').strip()

def make_request(url, headers_dict, payload_dict=None, timeout_sec=90):
    req = urllib2.Request(url)
    req.add_header("User-Agent", "iTunesGeniusAI/1.0 (macOS)")
    
    curl_headers = ["-H", "User-Agent: iTunesGeniusAI/1.0 (macOS)"]
    
    for k, v in headers_dict.items():
        if isinstance(k, unicode): k = k.encode('utf-8')
        if isinstance(v, unicode): v = v.encode('utf-8')
        req.add_header(k, v)
        curl_headers.extend(["-H", "{}: {}".format(k, v)])
        
    data = None
    if payload_dict:
        data = json.dumps(payload_dict, ensure_ascii=False).encode('utf-8')
        req.add_header('Content-Type', 'application/json')
        curl_headers.extend(["-H", "Content-Type: application/json"])
        
    def do_curl():
        cmd = ["curl", "-sSL", "-m", str(timeout_sec)] + curl_headers
        tmp_path = None
        if data:
            import tempfile
            tmp_fd, tmp_path = tempfile.mkstemp(suffix=".json")
            with os.fdopen(tmp_fd, 'wb') as f:
                f.write(data)
            cmd.extend(["-d", "@" + tmp_path])
            
        cmd.append(url)
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, err = p.communicate()
            if tmp_path:
                try: os.remove(tmp_path)
                except: pass
            if p.returncode == 0:
                return True, out
            return False, "Curl Error: " + err
        except Exception as ce:
            if tmp_path:
                try: os.remove(tmp_path)
                except: pass
            return False, "Curl Exception: " + str(ce)

    try:
        try:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            response = urllib2.urlopen(req, data=data, context=ctx, timeout=timeout_sec)
        except AttributeError:
            response = urllib2.urlopen(req, data=data, timeout=timeout_sec)
        return True, response.read()
    except urllib2.HTTPError as e:
        if e.code in [401, 403]: 
            return True, e.read()
        return False, "HTTP Error: {} - {}".format(e.code, e.read()[:100])
    except Exception as e:
        err_str = str(e).lower()
        if "ssl" in err_str or "handshake" in err_str or "errno 1" in err_str or "socket error" in err_str or "eof" in err_str:
            return do_curl()
        return False, "Network Error: " + str(e)

def test_api_key(provider, api_key, model):
    if provider == "Groq":
        url = "https://api.groq.com/openai/v1/chat/completions"
        payload = {"model": model.strip(), "messages": [{"role": "user", "content": "Say 'OK'"}], "max_tokens": 10}
        headers = {"Authorization": "Bearer " + api_key.strip()}
    elif provider == "OpenRouter":
        url = "https://openrouter.ai/api/v1/chat/completions"
        payload = {"model": model.strip(), "messages": [{"role": "user", "content": "Say 'OK'"}], "max_tokens": 10}
        headers = {
            "Authorization": "Bearer " + api_key.strip(),
            "HTTP-Referer": "https://github.com/YuraMenschikov/iTunesGeniusAI",
            "X-Title": "iTunesGeniusAI"
        }
    else:
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}".format(model.strip(), api_key.strip())
        payload = {"contents": [{"parts": [{"text": "Say 'OK'"}]}], "generationConfig": {"maxOutputTokens": 10}}
        headers = {}

    ok, result = make_request(url, headers, payload, timeout_sec=120)
    if not ok: return False, result

    try:
        resp = json.loads(result)
        if provider == "Groq" or provider == "OpenRouter":
            if "choices" in resp: return True, "OK"
            err_msg = resp.get("error", {}).get("message", "Unknown Error")
            return False, err_msg + "\n\nFULL RESPONSE:\n" + result
        else:
            if "candidates" in resp: return True, "OK"
            err_msg = resp.get("error", {}).get("message", "Unknown Gemini Error")
            return False, err_msg + "\n\nFULL RESPONSE:\n" + result
    except Exception as e:
        return False, "Parse Error: " + str(e) + "\nRaw: " + result

def call_ai_for_playlist(provider, api_key, model, prompt_text):
    if provider == "Groq":
        url = "https://api.groq.com/openai/v1/chat/completions"
        payload = {
            "model": model.strip(), 
            "messages": [
                {"role": "system", "content": "You are a strict data API. You MUST output ONLY a valid JSON array of strings. You must NEVER output conversational text, introductions, or markdown. Output exactly what is requested and nothing else."},
                {"role": "user", "content": prompt_text}
            ], 
            "temperature": 0.3
        }
        headers = {"Authorization": "Bearer " + api_key.strip()}
    elif provider == "OpenRouter":
        url = "https://openrouter.ai/api/v1/chat/completions"
        payload = {
            "model": model.strip(), 
            "messages": [
                {"role": "system", "content": "You are a strict data API. You MUST output ONLY a valid JSON array of strings. You must NEVER output conversational text, introductions, or markdown. Output exactly what is requested and nothing else."},
                {"role": "user", "content": prompt_text}
            ], 
            "temperature": 0.3
        }
        headers = {
            "Authorization": "Bearer " + api_key.strip(),
            "HTTP-Referer": "https://github.com/YuraMenschikov/iTunesGeniusAI",
            "X-Title": "iTunesGeniusAI"
        }
    else:
        url = "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent?key={}".format(model.strip(), api_key.strip())
        payload = {"contents": [{"parts": [{"text": prompt_text}]}]}
        headers = {}

    ok, result = make_request(url, headers, payload, timeout_sec=120)
    if not ok: return False, result
    
    try:
        resp = json.loads(result)
        if provider == "Groq" or provider == "OpenRouter":
            text = resp["choices"][0]["message"]["content"]
        else:
            text = resp["candidates"][0]["content"]["parts"][0]["text"]
        return True, text
    except Exception as e:
        return False, "Failed to parse AI response: " + str(e) + "\nRaw: " + result

def get_library(progress_cb, check_run):
    try:
        total = int(run_as('tell application "iTunes" to count every track'))
    except:
        return []
    
    library = []
    chunk_size = 200
    for i in range(1, total + 1, chunk_size):
        if not check_run(): break
        end_idx = min(i + chunk_size - 1, total)
        script = u'''
        set out to ""
        tell application "iTunes"
            set trks to (tracks {0} thru {1} of library playlist 1)
            repeat with t in trks
                set pid to ""
                set art to ""
                set nm to ""
                set gen to ""
                set yr to ""
                try
                    set pid to persistent ID of t
                    set art to artist of t
                    set nm to name of t
                end try
                try
                    set gen to genre of t
                end try
                try
                    set yr to year of t
                end try
                if pid is not "" and art is not "" and nm is not "" then
                    set out to out & pid & "|" & art & "|" & nm & "|" & gen & "|" & yr & "\\n"
                end if
            end repeat
        end tell
        return out
        '''.format(i, end_idx)
        
        res = run_as(script)
        for line in res.split('\n'):
            if "|" in line:
                library.append(line.strip())
        progress_cb(end_idx, total)
    return library

def create_itunes_playlist(name, ids_list):
    script = u'''
    tell application "iTunes"
        set plName to "{0}"
        if not (exists user playlist plName) then
            make new user playlist with properties {{name:plName}}
        end if
        set pl to user playlist plName
        delete every track of pl
        
        set addedCount to 0
        set idList to {1}
        
        repeat with tid in idList
            try
                set trk to (some track of library playlist 1 whose persistent ID is tid)
                duplicate trk to pl
                set addedCount to addedCount + 1
            end try
        end repeat
        return addedCount as string
    end tell
    '''.format(name.replace('"', '\\"'), '{"' + '", "'.join(ids_list) + '"}')
    return run_as(script.encode('utf-8'))


class SetupWindow(tk.Toplevel):
    def __init__(self, parent, on_success):
        tk.Toplevel.__init__(self, parent)
        self.title(_(u"menu_ai_settings").replace("...", ""))
        
        window_width = 750
        window_height = 540
        self.geometry("{}x{}".format(window_width, window_height))
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        
        self.on_success = on_success
        self.configure(bg="#ECECEC")
        
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry("+{}+{}".format((sw - window_width)//2, (sh - window_height)//2))
        
        main_frame = tk.Frame(self, bg="#ECECEC")
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=(20, 10))
        
        # --- PROVIDER SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_provider") if "setup_grp_provider" in LANGUAGES["en"] else "AI Provider", font=("system", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 5))
        
        self.provider_var = tk.StringVar(value=CONFIG_DATA.get("provider", "Gemini"))
        frame_prov = tk.Frame(main_frame, bg="#ECECEC")
        frame_prov.pack(anchor="w", padx=10, pady=5)
        tk.Radiobutton(frame_prov, text="Google Gemini", variable=self.provider_var, value="Gemini", command=self.update_models, font=("system", 13), bg="#ECECEC").pack(side=tk.LEFT, padx=(0, 15))
        tk.Radiobutton(frame_prov, text="Groq", variable=self.provider_var, value="Groq", command=self.update_models, font=("system", 13), bg="#ECECEC").pack(side=tk.LEFT, padx=15)
        tk.Radiobutton(frame_prov, text="OpenRouter", variable=self.provider_var, value="OpenRouter", command=self.update_models, font=("system", 13), bg="#ECECEC").pack(side=tk.LEFT, padx=15)
        
        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        # --- CONNECTION SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_conn") if "setup_grp_conn" in LANGUAGES["en"] else "Connection Settings", font=("system", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 10))
        
        conn_frame = tk.Frame(main_frame, bg="#ECECEC")
        conn_frame.pack(fill=tk.X, padx=10)
        conn_frame.columnconfigure(1, weight=1)
        
        # Row 0: Model
        tk.Label(conn_frame, text=_(u"setup_model"), font=("system", 12), bg="#ECECEC").grid(row=0, column=0, sticky="w", pady=10, padx=(0, 10))
        self.model_var = tk.StringVar()
        self.model_dropdown = ttk.Combobox(conn_frame, textvariable=self.model_var, font=("system", 13))
        self.model_dropdown.grid(row=0, column=1, sticky="we", pady=10)
        
        self.btn_sync = tk.Button(conn_frame, text=_(u"btn_sync") if "btn_sync" in LANGUAGES["en"] else "SYNC MODELS", command=lambda: self.update_models(force_sync=True), highlightbackground="#ECECEC", font=("system", 12), width=22)
        self.btn_sync.grid(row=0, column=2, sticky="we", padx=(15, 0), pady=10)
        
        self.apply_local_models()
        if CONFIG_DATA.get("model"):
            self.model_var.set(CONFIG_DATA.get("model"))
            
        # Row 1: Key
        tk.Label(conn_frame, text=_(u"setup_key"), font=("system", 12), bg="#ECECEC").grid(row=1, column=0, sticky="w", pady=10, padx=(0, 10))
        self.api_key_entry = tk.Entry(conn_frame, show="*", font=("system", 14), highlightbackground="#ECECEC")
        self.api_key_entry.insert(0, CONFIG_DATA.get("api_key", ""))
        self.api_key_entry.grid(row=1, column=1, sticky="we", pady=10)
        
        # --- SHOW KEY & PASTE BUTTONS ---
        btn_frame = tk.Frame(conn_frame, bg="#ECECEC")
        btn_frame.grid(row=1, column=1, sticky="e", padx=(0, 2))
        
        self.show_key_var = tk.BooleanVar(value=False)
        def toggle_key():
            if self.show_key_var.get(): self.api_key_entry.config(show="")
            else: self.api_key_entry.config(show="*")
            
        tk.Checkbutton(btn_frame, text="", variable=self.show_key_var, command=toggle_key, bg="#ECECEC", highlightthickness=0).pack(side=tk.LEFT)
        
        def quick_paste():
            try:
                text = self.clipboard_get()
                if text:
                    self.api_key_entry.delete(0, tk.END)
                    self.api_key_entry.insert(0, text)
            except: pass
            
        tk.Button(btn_frame, text="PASTE", command=quick_paste, font=("system", 9), highlightbackground="#ECECEC", padx=2, pady=0).pack(side=tk.LEFT, padx=(2, 0))
        
        self.btn_save = tk.Button(conn_frame, text=_(u"setup_btn"), command=self.validate, highlightbackground="#ECECEC", font=("system", 12), width=22)
        self.btn_save.grid(row=1, column=2, sticky="we", padx=(15, 0), pady=10)
        
        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        
        # --- LIBRARY SECTION ---
        tk.Label(main_frame, text=_(u"setup_grp_lib") if "setup_grp_lib" in LANGUAGES["en"] else "iTunes Library", font=("system", 13), bg="#ECECEC").pack(anchor="w", pady=(0, 10))
        
        lib_frame = tk.Frame(main_frame, bg="#ECECEC")
        lib_frame.pack(fill=tk.X, padx=10)
        
        self.btn_sync_lib = tk.Button(lib_frame, text=_(u"btn_sync_lib") if "btn_sync_lib" in LANGUAGES["en"] else "SYNC LIBRARY", command=self.clear_lib_cache, highlightbackground="#ECECEC", font=("system", 12), width=22)
        self.btn_sync_lib.pack(side=tk.LEFT, pady=10)

        tk.Frame(main_frame, bg="#D4D4D4", height=1).pack(fill=tk.X, pady=15)
        
        # --- PREFERENCES SECTION ---
        pref_frame = tk.Frame(main_frame, bg="#ECECEC")
        pref_frame.pack(fill=tk.X)
        
        self.log_pref_var = tk.BooleanVar(value=CONFIG_DATA.get("prompt_logs", True))
        tk.Checkbutton(pref_frame, text=_(u"setup_log_pref") if "setup_log_pref" in LANGUAGES["en"] else "Ask to save text logs", variable=self.log_pref_var, bg="#ECECEC", font=("system", 12), command=self.save_log_pref).pack(side=tk.LEFT, anchor="w", padx=10, pady=0)
        
        # --- FOOTER SECTION ---
        bottom_frame = tk.Frame(main_frame, bg="#ECECEC")
        bottom_frame.pack(side=tk.BOTTOM, fill=tk.X, pady=(20, 0))
        
        tk.Label(bottom_frame, text=_(u"footer"), font=("system", 10), fg="#666666", bg="#ECECEC", justify=tk.CENTER).pack(side=tk.LEFT, expand=True)
        
        self.help_canvas = tk.Canvas(bottom_frame, width=28, height=28, bg="#ECECEC", highlightthickness=0)
        self.help_canvas.pack(side=tk.RIGHT, anchor="se")
        self.help_bg = self.help_canvas.create_oval(2, 2, 26, 26, outline="#999999", fill="#EAEAEA", width=1)
        self.help_text = self.help_canvas.create_text(14, 14, text="?", font=("system", 14, "bold"), fill="#555555")
        
        self.help_canvas.bind("<Button-1>", lambda e: self.show_help())
        self.help_canvas.bind("<Enter>", lambda e: self.on_help_hover(True))
        self.help_canvas.bind("<Leave>", lambda e: self.on_help_hover(False))
        
        self.protocol("WM_DELETE_WINDOW", self.on_closing)

    def on_help_hover(self, is_hover):
        if is_hover:
            self.help_canvas.itemconfig(self.help_bg, fill="#D0D0D0", outline="#666666")
            self.help_canvas.itemconfig(self.help_text, fill="#222222")
            self.help_canvas.config(cursor="pointinghand")
        else:
            self.help_canvas.itemconfig(self.help_bg, fill="#EAEAEA", outline="#999999")
            self.help_canvas.itemconfig(self.help_text, fill="#555555")
            self.help_canvas.config(cursor="")

    def save_log_pref(self):
        CONFIG_DATA["prompt_logs"] = self.log_pref_var.get()
        save_config(CONFIG_DATA)
        
    def clear_lib_cache(self):
        self.btn_sync_lib.config(state="disabled")
        self.prog_win = ProgressWindow(self)
        
        def task():
            try:
                def update_progress(curr, total):
                    self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                    self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_read", curr, total)))
                    
                lib = get_library(update_progress, lambda: self.prog_win.running)
                
                if not self.prog_win.running:
                    self.after(0, self.prog_win.destroy)
                    self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
                    return
                    
                self.master.cached_library = lib
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: tkMessageBox.showinfo("Sync", _(u"msg_lib_synced") if "msg_lib_synced" in LANGUAGES["en"] else "Library cache updated!"))
                self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
            except Exception as e:
                self.after(0, self.prog_win.destroy)
                self.after(0, lambda: tkMessageBox.showerror("Error", str(e)))
                self.after(0, lambda: self.btn_sync_lib.config(state="normal"))
                
        import threading
        threading.Thread(target=task).start()


    def on_closing(self):
        self.grab_release()
        if not CONFIG_DATA.get("api_key"):
            self.master.quit()
            self.master.destroy()
            sys.exit(0)
        else:
            self.destroy()

    def show_help(self):
        tkMessageBox.showinfo(_(u"help_title"), _(u"help_text"))

    def apply_local_models(self):
        models_dict = {
            "Gemini": ["gemini-1.5-flash-latest", "gemini-pro", "gemini-1.5-flash", "gemini-1.5-pro", "gemini-2.0-flash-exp"],
            "Groq": ["llama3-70b-8192", "mixtral-8x7b-32768", "llama3-8b-8192", "llama-3.1-70b-versatile"],
            "OpenRouter": ["meta-llama/llama-3.3-70b-instruct:free", "deepseek/deepseek-r1-distill-llama-70b:free", "google/gemma-4-26b-a4b-it:free", "deepseek/deepseek-v4-flash:free", "qwen/qwen2.5-72b-instruct:free"]
        }
        prov = self.provider_var.get()
        models = models_dict.get(prov, [])
        self.model_dropdown['values'] = models
        current = self.model_var.get()
        if current not in models and models:
            self.model_var.set(models[0])

    def update_models(self, force_sync=False):
        if force_sync:
            prov = self.provider_var.get()
            if prov != "OpenRouter":
                tkMessageBox.showinfo("Sync", "Auto-sync is only available for OpenRouter.")
                return
                
            self.btn_sync.config(state="disabled")
            self.update_idletasks()
            
            def fetch():
                try:
                    url = "https://openrouter.ai/api/v1/models"
                    ok, out = make_request(url, {}, timeout_sec=15)
                    if ok and out:
                        data = json.loads(out)
                        free_models = [m['id'] for m in data.get('data', []) if ':free' in m['id']]
                        if free_models:
                            free_models.sort()
                            self.after(0, self.apply_synced_models, free_models, prov)
                            return
                        else:
                            self.after(0, self.fail_sync, "No free models found.")
                            return
                    else:
                        self.after(0, self.fail_sync, "Error: " + str(out)[:100])
                        return
                except Exception as e:
                    self.after(0, self.fail_sync, "Exception: " + str(e)[:100])
                    return
                
            import threading
            threading.Thread(target=fetch).start()
        else:
            self.apply_local_models()
            
    def apply_synced_models(self, models, requested_prov):
        if self.provider_var.get() != requested_prov:
            self.btn_sync.config(state="normal")
            return
            
        self.model_dropdown['values'] = models
        current = self.model_var.get()
        if current not in models and models:
            self.model_var.set(models[0])
        self.btn_sync.config(state="normal")
        tkMessageBox.showinfo("Sync", _(u"sync_success") if "sync_success" in LANGUAGES["en"] else "Models updated successfully!")
        
    def fail_sync(self, err_msg="Failed to sync models"):
        self.btn_sync.config(state="normal")
        tkMessageBox.showerror("Sync", err_msg)

    def validate(self):
        prov = self.provider_var.get()
        mod = self.model_var.get()
        key = self.api_key_entry.get().strip()
        
        if not key:
            tkMessageBox.showerror("Error", _(u"err_no_key"))
            return
            
        self.btn_save.config(state='disabled')
        self.update()
        
        def check():
            try:
                ok, msg = test_api_key(prov, key, mod)
            except Exception as e:
                ok, msg = False, "Internal error: " + str(e)
            self.after(0, self.finish_validate, ok, msg, prov, mod, key)
            
        threading.Thread(target=check).start()

    def finish_validate(self, ok, msg, prov, mod, key):
        self.btn_save.config(state='normal')
        if ok:
            CONFIG_DATA["provider"] = prov
            CONFIG_DATA["model"] = mod
            CONFIG_DATA["api_key"] = key
            save_config(CONFIG_DATA)
            tkMessageBox.showinfo("Success", _(u"status_success"))
            self.on_success()
            self.grab_release()
            self.destroy()
        else:
            user_msg = _(u"err_conn")
            if "401" in msg or "Authentication" in msg or "User not found" in msg:
                user_msg = _(u"err_invalid_key")
            elif "404" in msg or "endpoints found" in msg.lower() or "not a valid model id" in msg.lower():
                user_msg = _(u"err_invalid_model")
            elif "429" in msg or "overloaded" in msg.lower() or "Provider returned error" in msg:
                user_msg = _(u"err_429")
            
            if CONFIG_DATA.get("prompt_logs", True):
                save_log = tkMessageBox.askyesno("Connection Error", user_msg + "\n\n" + _(u"ask_save_log"))
                if save_log:
                    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
                    log_file = os.path.join(desktop, "iTunesGenius_Validation_Error.txt")
                    try:
                        with open(log_file, "w") as f:
                            f.write("API VALIDATION ERROR LOG\n")
                            f.write("Provider: " + prov + "\n")
                            f.write("Model: " + mod + "\n")
                            f.write("-" * 30 + "\n")
                            f.write(msg + "\n")
                        tkMessageBox.showinfo(_(u"log_saved_title"), _(u"log_saved_msg").format("iTunesGenius_Validation_Error.txt"))
                    except: pass
            else:
                tkMessageBox.showerror("Connection Error", user_msg)

class ProgressWindow(tk.Toplevel):
    def __init__(self, parent):
        tk.Toplevel.__init__(self, parent)
        self.title(_(u"prog_title"))
        self.geometry("440x290")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self.configure(bg="#ECECEC")
        
        s = ttk.Style()
        s.configure("TProgressbar", thickness=30)
        
        self.lbl = tk.Label(self, text=_(u"prog_start"), font=("system", 13, "bold"), bg="#ECECEC")
        self.lbl.pack(pady=(20, 10))
        
        self.progress = ttk.Progressbar(self, orient="horizontal", length=400, mode="determinate", style="TProgressbar")
        self.progress.pack(pady=5, padx=20)
        
        console_frame = tk.Frame(self, bg="#ECECEC")
        console_frame.pack(padx=20, pady=(10, 5), fill=tk.BOTH, expand=True)
        
        self.console_scroll = ttk.Scrollbar(console_frame)
        self.console_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.console = tk.Text(console_frame, height=5, font=("system", 10), bg="#1E1E1E", fg="#00FF00", highlightthickness=0, state="disabled", yscrollcommand=self.console_scroll.set)
        self.console.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.console_scroll.config(command=self.console.yview)
        
        cancel_frame = tk.Frame(self, bg="#ECECEC")
        cancel_frame.pack(pady=(5, 10))
        
        self.lbl_cancel = tk.Label(cancel_frame, text=_(u"prog_stop"), font=("system", 11), bg="#ECECEC", fg="#555555")
        self.lbl_cancel.pack(side=tk.LEFT, padx=(0, 10))
        
        self.btn_cancel = tk.Button(cancel_frame, text="X", command=self.cancel, fg="#555555", font=("system", 11, "bold"), highlightbackground="#ECECEC", width=2)
        self.btn_cancel.pack(side=tk.LEFT)
        
        self.running = True
        self.fun_active = False
        self.fun_idx = 0
        
    def log(self, text):
        self.console.config(state="normal")
        self.console.insert("end", "> " + text + "\n")
        self.console.see("end")
        self.console.config(state="disabled")
        self.update_idletasks()
        
    def start_fun_messages(self):
        self.fun_active = True
        self.fun_idx = 0
        self.after(5000, self._next_fun_msg)
        
    def _next_fun_msg(self):
        if not self.running or not self.fun_active or not self.winfo_exists():
            return
            
        lang = CONFIG_DATA.get("lang", "en")
        msgs_dict = {
            "en": ["Analyzing your musical taste...", "Asking the neighbor for advice...", "The AI went to microwave some food...", "Sit back and relax...", "Still thinking... AI needs coffee."],
            "ru": [u"Анализируем ваш музыкальный вкус...", u"Даём послушать треки соседу...", u"ИИ пошёл греть еду в микроволновке...", u"Откиньтесь на спинку кресла и отдохните...", u"Всё ещё думаем... ИИ нужен кофе."],
            "be": [u"Аналізуем ваш музычны густ...", u"Даём паслухаць трэкі суседу...", u"ШІ пайшоў грэць ежу ў мікрахвалеўцы...", u"Адкіньцеся на спінку крэсла і адпачніце...", u"Усё яшчэ думаем... ШІ патрэбна кава."]
        }
        msgs = msgs_dict.get(lang, msgs_dict["en"])
        
        if msgs:
            self.lbl.config(text=msgs[self.fun_idx])
            self.fun_idx = (self.fun_idx + 1) % len(msgs)
            
        self.after(10000, self._next_fun_msg)
        
    def cancel(self):
        self.running = False
        self.fun_active = False
        self.lbl.config(text=_(u"prog_canceling"))
        self.btn_cancel.config(state="disabled")

class App(tk.Tk):
    def __init__(self):
        tk.Tk.__init__(self)
        self.title("iGeniusAI")
        self.geometry("600x550")
        self.resizable(False, False)
        self.configure(bg="#ECECEC")
        
        # Попытка установить иконку для окон (в macOS работает не всегда, но если поддерживается — применится)
        try:
            icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "appIcon.icns")
            if os.path.exists(icon_path):
                self.iconbitmap(icon_path)
        except: pass
        
        w, h = 600, 550
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        self.geometry("{}x{}+{}+{}".format(w, h, int(sw/2 - w/2), int(sh/2 - h/2)))
        
        try:
            # Проверяем, запущен ли iTunes, чтобы не открывать его принудительно при старте
            is_running = run_as('tell application "System Events" to (name of processes) contains "iTunes"')
            if is_running.lower() == "true":
                self.total_tracks = int(run_as('tell application "iTunes" to count every track'))
            else:
                self.total_tracks = "?"
        except:
            self.total_tracks = "?"

        self.build_menu()

        self.main_container = tk.Frame(self, bg="#ECECEC")
        self.main_container.pack(fill=tk.BOTH, expand=True)
        
        self.cached_library = None

        self.build_ui()
        self.protocol("WM_DELETE_WINDOW", self.on_closing)
        
        # --- GLOBAL SHORTCUTS FOR MAC ---
        self.bind_all("<Command-v>", lambda e: self.focus_get().event_generate("<<Paste>>"))
        self.bind_all("<Command-c>", lambda e: self.focus_get().event_generate("<<Copy>>"))
        self.bind_all("<Command-x>", lambda e: self.focus_get().event_generate("<<Cut>>"))
        self.bind_all("<Command-a>", lambda e: self.focus_get().event_generate("<<SelectAll>>"))
        
        # --- RIGHT CLICK CONTEXT MENU ---
        def show_context_menu(event):
            try:
                # Only show for Entry and Text widgets
                if not isinstance(event.widget, (tk.Entry, tk.Text)): return
                
                menu = tk.Menu(self, tearoff=0)
                menu.add_command(label="Cut", command=lambda: event.widget.event_generate("<<Cut>>"))
                menu.add_command(label="Copy", command=lambda: event.widget.event_generate("<<Copy>>"))
                menu.add_command(label="Paste", command=lambda: event.widget.event_generate("<<Paste>>"))
                menu.add_separator()
                menu.add_command(label="Select All", command=lambda: event.widget.event_generate("<<SelectAll>>"))
                menu.tk_popup(event.x_root, event.y_root)
            except: pass

        self.bind_all("<Button-2>", show_context_menu) # Right click on Mac
        self.bind_all("<Control-Button-1>", show_context_menu) # Ctrl + Click on Mac

        self.withdraw()
        
        # SSL Verification Check for old macOS
        import ssl
        if "0.9.8" in getattr(ssl, 'OPENSSL_VERSION', '') and not CONFIG_DATA.get("ssl_prompted"):
            CONFIG_DATA["ssl_prompted"] = True
            save_config(CONFIG_DATA)
            msg = _(u"ssl_update_msg") if "ssl_update_msg" in LANGUAGES["en"] else "Update recommended."
            if tkMessageBox.askyesno("Security Update", msg):
                import webbrowser
                webbrowser.open("https://www.python.org/ftp/python/2.7.18/python-2.7.18-macosx10.9.pkg")
                
        if not CONFIG_DATA.get("api_key"):
            SetupWindow(self, self.deiconify)
        else:
            self.deiconify()
            
    def change_lang(self, lang_code):
        CONFIG_DATA["lang"] = lang_code
        save_config(CONFIG_DATA)
        
        # Получаем переведенное сообщение о необходимости перезапуска
        msg = LANGUAGES.get(lang_code, LANGUAGES["en"]).get("restart_required", "Please restart the application to apply the selected language.")
        
        # tkMessageBox.showinfo по умолчанию имеет только одну кнопку "ОК"
        tkMessageBox.showinfo("Language", msg)
        
        # Полностью убиваем процесс (приложение закроется)
        self.quit()
        self.destroy()
        sys.exit(0)
        
    def build_menu(self):
        # Полностью пересоздаем меню для надежности на Mac
        self.menubar = tk.Menu(self)
        self.config(menu=self.menubar)
        
        self.app_menu = tk.Menu(self.menubar, tearoff=0)
        self.app_menu.add_command(label=_(u"menu_ai_settings"), command=self.open_settings)
        self.menubar.add_cascade(label=_(u"menu_settings"), menu=self.app_menu)
        
        # --- EDIT MENU (Required for Cmd+C/V on Mac) ---
        self.edit_menu = tk.Menu(self.menubar, tearoff=0)
        self.edit_menu.add_command(label="Cut", accelerator="Cmd+X", command=lambda: self.focus_get().event_generate("<<Cut>>"))
        self.edit_menu.add_command(label="Copy", accelerator="Cmd+C", command=lambda: self.focus_get().event_generate("<<Copy>>"))
        self.edit_menu.add_command(label="Paste", accelerator="Cmd+V", command=lambda: self.focus_get().event_generate("<<Paste>>"))
        self.edit_menu.add_command(label="Select All", accelerator="Cmd+A", command=lambda: self.focus_get().event_generate("<<SelectAll>>"))
        self.menubar.add_cascade(label="Edit", menu=self.edit_menu)

        self.lang_menu = tk.Menu(self.menubar, tearoff=0)
        self.lang_menu.add_command(label="English", command=lambda: self.change_lang("en"))
        self.lang_menu.add_command(label=u"Русский", command=lambda: self.change_lang("ru"))
        self.lang_menu.add_command(label=u"Беларуская", command=lambda: self.change_lang("be"))
        self.lang_menu.add_command(label=u"한국어", command=lambda: self.change_lang("ko"))
        self.lang_menu.add_command(label=u"日本語", command=lambda: self.change_lang("ja"))
        self.lang_menu.add_command(label=u"中文", command=lambda: self.change_lang("zh"))
        self.lang_menu.add_command(label="Deutsch", command=lambda: self.change_lang("de"))
        self.lang_menu.add_command(label="Polski", command=lambda: self.change_lang("pl"))
        self.lang_menu.add_command(label="Eesti", command=lambda: self.change_lang("et"))
        self.lang_menu.add_command(label="Español", command=lambda: self.change_lang("es"))
        self.menubar.add_cascade(label=_(u"menu_language"), menu=self.lang_menu)

    def build_ui(self):
        # Очищаем только контейнер формы
        for widget in self.main_container.winfo_children():
            widget.destroy()
            
        form_frame = tk.Frame(self.main_container, bg="#ECECEC")
        form_frame.pack(pady=10, fill=tk.BOTH, expand=True)

        tk.Label(form_frame, text=_(u"pl_name"), font=("system", 13), bg="#ECECEC").pack(anchor="w", padx=40, pady=(5, 2))
        self.pl_name = tk.Entry(form_frame, state="normal", font=("system", 14), highlightbackground="#ECECEC")
        self.pl_name.insert(0, _(u"def_name"))
        self.pl_name.pack(fill=tk.X, padx=40, pady=(0, 15))
        
        tk.Label(form_frame, text=_(u"pl_mood"), font=("system", 13), bg="#ECECEC").pack(anchor="w", padx=40, pady=(5, 2))
        self.pl_mood = tk.Entry(form_frame, state="normal", font=("system", 14), highlightbackground="#ECECEC")
        self.pl_mood.pack(fill=tk.X, padx=40, pady=(0, 15))
        
        tk.Label(form_frame, text=_(u"pl_count", str(self.total_tracks)), font=("system", 12), bg="#ECECEC").pack(anchor="w", padx=40, pady=(5, 2))
        self.count_var = tk.StringVar(value="25")
        
        count_frame = tk.Frame(form_frame, bg="#ECECEC")
        count_frame.pack(anchor="center", pady=(0, 15))
        
        def dec_count():
            try:
                val = int(self.count_var.get())
                if val > 1: self.count_var.set(str(val - 1))
            except: self.count_var.set("1")
            
        def inc_count():
            try:
                val = int(self.count_var.get())
                max_val = int(self.total_tracks) if str(self.total_tracks).isdigit() else 500
                if val < max_val: self.count_var.set(str(val + 1))
            except: self.count_var.set("25")

        tk.Button(count_frame, text="-", command=dec_count, width=2, highlightbackground="#ECECEC").pack(side=tk.LEFT)
        self.pl_count = tk.Entry(count_frame, textvariable=self.count_var, font=("system", 14), width=8, justify=tk.CENTER, highlightbackground="#ECECEC")
        self.pl_count.pack(side=tk.LEFT, padx=10)
        tk.Button(count_frame, text="+", command=inc_count, width=2, highlightbackground="#ECECEC").pack(side=tk.LEFT)
        
        self.btn_gen = ttk.Button(self.main_container, text=_(u"btn_gen"), command=self.start_generation)
        self.btn_gen.pack(pady=20, fill=tk.X, padx=40)
        
        tk.Label(self.main_container, text=_(u"footer"), font=("system", 10), fg="#666666", bg="#ECECEC", justify=tk.CENTER).pack(side=tk.BOTTOM, pady=15)

    def on_closing(self):
        self.quit()
        self.destroy()
        sys.exit(0)

    def open_settings(self):
        SetupWindow(self, lambda: None)

    def start_generation(self):
        mood = self.pl_mood.get().strip()
        name = self.pl_name.get().strip()
        count = self.pl_count.get()
        
        if not mood or not name:
            tkMessageBox.showerror("Error", _(u"err_fill_all"))
            return
            
        self.prog_win = ProgressWindow(self)
        threading.Thread(target=self.process_task, args=(mood, name, count)).start()

    def process_task(self, mood, name, count):
        try:
            def update_progress(curr, total):
                self.after(0, lambda: self.prog_win.progress.config(value=curr, maximum=total))
                self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_read", curr, total)))
            
            def slog(txt):
                self.after(0, lambda: self.prog_win.log(txt))
                
            slog("Initializing generation process...")
                
            if not self.cached_library:
                slog("Scanning iTunes Library (may take a moment)...")
                lib = get_library(update_progress, lambda: self.prog_win.running)
                
                if not self.prog_win.running:
                    self.after(0, self.prog_win.destroy)
                    return
                    
                if not lib:
                    raise Exception(_(u"err_empty_lib"))
                    
                slog("Successfully cached %d tracks." % len(lib))
                self.cached_library = lib
            else:
                lib = self.cached_library
                slog("Using cached iTunes library (%d tracks)." % len(lib))
                # Мгновенно заполняем прогресс-бар чтения
                update_progress(len(lib), len(lib))
                
            self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_ask")))
            self.after(0, lambda: self.prog_win.progress.config(mode="indeterminate"))
            self.after(0, self.prog_win.progress.start)
            self.after(0, self.prog_win.start_fun_messages)
            
            slog("Preparing prompt payload for AI...")
            prompt = u"""You are an expert DJ AI.
Create a playlist from the provided library.
Event/Mood requested: {mood}
Target Track Count: {count}

Library format: PersistentID|Artist|Title|Genre|Year
{library}

CRITICAL RULES:
1. Select exactly {count} tracks. If you cannot find perfect matches, select the closest alternatives based on artist style or genre to ensure you reach the target count.
2. You MUST return ONLY the 16-character hexadecimal PersistentID for each selected track.
3. DO NOT return track titles or artist names. Only the IDs (the first part of each line).
4. Your ENTIRE output MUST BE ONLY a single, flat JSON array of these ID strings.
5. DO NOT add explanations, notes, or markdown.
CORRECT OUTPUT FORMAT: ["A1B2C3D4E5F67890", "0987654321ABCDEF"]
""".format(mood=mood, count=count, library=u"\\n".join(lib))
            
            slog("Connecting to %s..." % CONFIG_DATA["provider"])
            slog("Awaiting AI response (this can take 10-60 seconds)...")
            ok, res = call_ai_for_playlist(CONFIG_DATA["provider"], CONFIG_DATA["api_key"], CONFIG_DATA["model"], prompt)
            
            if not self.prog_win.running:
                self.after(0, self.prog_win.destroy)
                return
                
            self.after(0, self.prog_win.progress.stop)
            self.after(0, lambda: self.prog_win.progress.config(mode="determinate", value=100))
            
            if not ok:
                slog("API Error received.")
                raise Exception(res)
                
            slog("Response received! Parsing JSON...")
                
            extracted_ids = re.findall(r'([a-fA-F0-9]{16})', str(res))
            if not extracted_ids: extracted_ids = re.findall(r'"([a-fA-F0-9]{10,20})"', str(res))
            if not extracted_ids: raise Exception(_(u"err_parse") + "\\n" + str(res)[:200])

            final_ids = []
            for tid in extracted_ids:
                if tid not in final_ids: final_ids.append(tid)
            final_ids = final_ids[:int(count)]
            
            slog("Found %d valid tracks. Injecting to iTunes..." % len(final_ids))
                
            self.after(0, lambda: self.prog_win.lbl.config(text=_(u"prog_create")))
            added_count = create_itunes_playlist(name, final_ids)
            slog("Playlist successfully created!")
            
            self.after(0, self.prog_win.destroy)
            
            def show_success():
                msg = _(u"msg_success", name, added_count)
                if CONFIG_DATA.get("prompt_logs", True):
                    save_log = tkMessageBox.askyesno("Success", msg + "\n\n" + _(u"ask_success_log"))
                    if save_log:
                        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
                        log_file = os.path.join(desktop, "iTunesGenius_Success_Log.txt")
                        try:
                            with open(log_file, "w") as f:
                                f.write("GENERATION SUCCESS LOG\n")
                                f.write("Model: " + CONFIG_DATA["model"] + "\n")
                                f.write("Mood: " + mood.encode('utf-8') + "\n")
                                f.write("Requested Count: " + str(count) + "\n")
                                f.write("Added to iTunes: " + str(added_count) + "\n")
                                f.write("-" * 30 + "\n")
                                f.write("AI RAW RESPONSE:\n" + res.encode('utf-8') + "\n")
                            tkMessageBox.showinfo(_(u"log_saved_title"), _(u"log_saved_msg", "iTunesGenius_Success_Log.txt"))
                        except: pass
                else:
                    tkMessageBox.showinfo("Success", msg)
                    
            self.after(0, show_success)
            
        except Exception as e:
            err_str = str(e)
            short_msg = _(u"err_unexp")
            if "429" in err_str: short_msg = _(u"err_429")
            elif "Failed to parse" in err_str: short_msg = _(u"err_parse")
            
            self.after(0, self.prog_win.destroy)
            
            def show_error_and_ask_log():
                if CONFIG_DATA.get("prompt_logs", True):
                    save_log = tkMessageBox.askyesno("Generation Error", short_msg + "\n\n" + _(u"ask_save_log"))
                    if save_log:
                        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
                        log_file = os.path.join(desktop, "iTunesGenius_Generation_Error.txt")
                        try:
                            with open(log_file, "w") as f:
                                f.write("GENERATION ERROR LOG\n")
                                f.write("Model: " + CONFIG_DATA["model"] + "\n")
                                f.write("User Input - Mood: " + mood.encode('utf-8') + "\n")
                                f.write("User Input - Name: " + name.encode('utf-8') + "\n")
                                f.write("User Input - Count: " + str(count) + "\n")
                                f.write("Provider: " + CONFIG_DATA["provider"] + "\n")
                                f.write("-" * 30 + "\n")
                                f.write(err_str + "\n")
                            tkMessageBox.showinfo(_(u"log_saved_title"), _(u"log_saved_msg", "iTunesGenius_Generation_Error.txt"))
                        except: pass
                else:
                    tkMessageBox.showerror("Generation Error", short_msg)
                    
            self.after(0, show_error_and_ask_log)


if __name__ == "__main__":
    app = App()
    app.mainloop()
