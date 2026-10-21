# תלויות, רישיונות ומקורות

הפרויקט כולל תלויות ומודלי צד שלישי. החבילה אינה מעניקה בעלות או רישיון חלופי עליהם. האפליקציה מציגה את רישיונות חבילות Flutter דרך ״רישיונות רכיבים״ במסך המידע.

| רכיב ישיר | גרסה | מקור |
| --- | --- | --- |
| Flutter / Dart | Flutter 3.47.7 | https://github.com/flutter/flutter |
| ultralytics_yolo | 0.6.16 | https://pub.dev/packages/ultralytics_yolo/versions/0.6.16 |
| permission_handler | 12.0.1 | https://pub.dev/packages/permission_handler/versions/12.0.1 |
| flutter_tts | 4.2.5 | https://pub.dev/packages/flutter_tts/versions/4.2.5 |
| path_provider | 2.1.6 | https://pub.dev/packages/path_provider/versions/2.1.6 |
| share_plus | 13.3.1 | https://pub.dev/packages/share_plus/versions/13.3.1 |

flutter_tts משתמש ברישיון MIT; share_plus משתמש ברישיון BSD-3-Clause. טקסטי הרישיונות המותקנים נארזים במנגנון רישיונות Flutter בעת הבנייה. פרטי תלויות עקיפות וגרסאותיהן נמצאים ב-pubspec.lock.

ל-Ultralytics יש מסלול AGPL-3.0 ומסלול Enterprise לפי תנאיו. יש לבדוק את תנאי המודלים והתוסף ואת דרישות הפצת המקור לפני הפצת APK למשתמשים מחוץ לצוות או שילוב במוצר סגור. אין כאן אישור לרישיון מסחרי, והמשקלים אינם כלולים בחבילת המקור. מקור: https://www.ultralytics.com/license .

תיקון הקול נשען על מקור חבילת flutter_tts 4.2.5: android/src/main/kotlin/com/eyedeadevelopment/fluttertts/FlutterTtsPlugin.kt, הפונקציה readVoiceProperties. השדה network_required נכתב שם כמחרוזת 0/1. נבדק בארכיון הרשמי https://pub.dev/api/archives/flutter_tts-4.2.5.tar.gz ב-21.10.2026.

ממשק share_plus נבדק ב-README ובמקור חבילת 13.3.1: https://pub.dev/api/archives/share_plus-13.3.1.tar.gz . פתיחת בוחר שיתוף אינה שליחה אוטומטית ואינה בוחרת נמען.
