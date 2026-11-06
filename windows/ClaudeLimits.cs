// Claude Limits для Windows: краб у треї показує ліміти Claude (сесія 5 год і тиждень).
// Логіка (бекоф, кеш, пороги, стани краба) перенесена один в один з src/main.swift.
// Збирається вбудованим у Windows компілятором C# 5 (див. build.cmd), тому тут немає новіших фішок мови.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

class Limit { public double Percent; public DateTime? Resets; }   // усі дати зберігаємо в UTC
class Usage { public Limit Session; public Limit Weekly; }

// Малює "пікселі" краба: одна клітинка сітки = K×K справжніх пікселів.
class Canvas {
    public Graphics G; public int X0, Y0, K, Ox;
    public void Cell(int x, int y, Color c, double h = 1, double dy = 0, bool fix = false) {
        int px = X0 + (x + (fix ? 1 : Ox)) * K;
        int py = Y0 + (int)Math.Floor((y + dy) * K);
        int ph = Math.Max(1, (int)Math.Round(h * K));
        using (var b = new SolidBrush(c)) G.FillRectangle(b, px, py, K, ph);
    }
}

// Піксельний маскот 13x10, анімований.
// Настрій: найбільший з лімітів; плюс сон уночі, паніка від 95%, свято після скидання ліміту, шапка взимку.
// Лише на Windows: стежить очима за мишкою, червоніє від наведення, п'є каву, обідає, диско в п'ятницю,
// сонний понеділок, іноді вдягає окуляри, гуляє по панелі, сумує без тебе й радіє, коли повертаєшся,
// бовтає ногами в руці, лякається чайки, на Хелловін — гарбуз на голові.
class Crab {
    public int CelebrateUntil, WaveUntil, CoolUntil, WelcomeUntil;
    public string Force;          // примусовий стан із дебаг-меню
    public bool LightTaskbar;     // світла панель задач: смужки малюємо темнішими
    public bool Hover;            // мишка над крабом
    public int LookDx;            // куди дивитися: -1 вліво, 0 прямо, 1 вправо
    public bool Walking;          // іде: ноги бігають швидше
    public bool Held;             // у повітрі (тримають мишкою або падає)
    public bool Dizzy;            // щойно впав: паморочиться
    public bool Scared, Angry;    // чайка над головою / щойно пролетіла
    public bool Lonely;           // тебе давно немає за комп'ютером
    public string Pose;           // поза на сцені: "fall" (падає), "fly" (летить), "snip" (клацає біля курсора)
    public bool Cyber;            // кіберпанк-режим: імплант біля ока, хромовані клешні
    public float Music;           // гучність музики зараз (0..1), 0 — тиша
    public int Beat;              // лічильник ударів музики: на кожен удар краб міняє позу

    static int MonthDay() { var n = DateTime.Now; return n.Month * 100 + n.Day; }
    public bool Winter { get { int md = MonthDay(); return md >= 1215 || md <= 110 || Force == "winter"; } }
    public bool Halloween { get { int md = MonthDay(); return (md >= 1025 && md <= 1101) || Force == "halloween"; } }

    static Color C(int r, int g, int b) { return Color.FromArgb(r, g, b); }
    static readonly Color Dark = C(31, 31, 31), Teal = C(64, 200, 224), Red = C(255, 59, 48), Zzz = C(191, 191, 191);
    static readonly Color Pumpkin = C(255, 140, 0), Stem = C(52, 199, 89), Blush = C(255, 105, 120);
    static readonly Color Mug = C(240, 240, 240), Coffee = C(111, 78, 55), Steam = C(170, 170, 170), Glint = C(110, 110, 110);
    static readonly Color Star = C(255, 214, 10), Fish = C(150, 185, 210), Heart = C(255, 77, 109);
    static readonly Color[] Confetti = { C(255, 204, 0), C(255, 45, 85), C(64, 200, 224), C(52, 199, 89), C(175, 82, 222) };
    static readonly string[] Rows = { "..XXXXXXX..", "..XXXXXXX..", "XXXXXXXXXXX", "XXXXXXXXXXX", "..XXXXXXX.." };

    // Квадратна іконка для трею size×size: зверху краб, знизу дві смужки (сесія і тиждень).
    public Bitmap Draw(double? pct, int f, int size, double? session, double? weekly) {
        int k = Math.Max(1, size / 16);
        int barH = Math.Max(2, size / 10), gap = Math.Max(1, size / 16);
        int barsH = 2 * barH + gap + 1;
        var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) {
            g.Clear(Color.Transparent);
            Paint(g, (size - 14 * k) / 2, Math.Max(0, (size - barsH - 10 * k) / 2), k, pct, f);
            // Смужки: зверху сесія (з поправкою -3, як і колір цифри на Mac), знизу тиждень.
            int by = size - 2 * barH - gap;
            Bar(g, by, barH, size, session, session - 3);
            Bar(g, by + barH + gap, barH, size, weekly, weekly);
        }
        return bmp;
    }

    // Малює краба: ділянка 14×10 клітинок з лівим верхнім кутом (x0, y0), клітинка = k×k пікселів.
    public void Paint(Graphics g, int x0, int y0px, int k, double? pct, int f) {
        double p = pct ?? 0;
        if (Pose == "psycho") { p = Math.Max(p, 97); Pose = null; }    // кіберпсихоз: завжди паніка
        var now = DateTime.Now;
        int md = now.Month * 100 + now.Day, dow = (int)now.DayOfWeek, hm = now.Hour * 100 + now.Minute;
        bool winter = md >= 1215 || md <= 110 || Force == "winter";
        bool halloween = (md >= 1025 && md <= 1101) || Force == "halloween";
        // Те, що відбувається з крабом «фізично», важливіше за настрій.
        bool fall = Pose == "fall" || Force == "fall", fly = !fall && (Pose == "fly" || Force == "fly");
        bool snipP = !fall && !fly && (Pose == "snip" || Force == "snip");
        bool held = !fall && !fly && !snipP && Held, dizzy = !held && Dizzy, scared = !fall && !fly && !snipP && !held && !dizzy && Scared;
        bool busy = fall || fly || snipP || held || dizzy || scared;
        bool valentine = md == 214 || Force == "valentine";
        bool flagDay = md == 824 || md == 628 || Force == "flag";       // День Незалежності / День Конституції
        bool welcome = !busy && (f < WelcomeUntil || Force == "welcome");
        bool angry = !busy && !welcome && Angry;
        bool party = !busy && !welcome && !angry && (f < CelebrateUntil || Force == "party");
        bool wave = !busy && !welcome && !angry && !party && (f < WaveUntil || Force == "wave");
        bool special = busy || welcome || angry || party || wave;
        // Уночі спить, але не тоді, коли в дебаг-меню вибрано інший стан.
        bool night = Force == null ? now.Hour < 7 || now.Hour >= 23 : Force == "sleep";
        bool musicOn = Music > 0 || Force == "dance";
        bool sleeping = !special && !Walking && !musicOn && pct.HasValue && p < 75 && night;   // музика будить
        bool panic = !special && p >= 95;
        bool chill = !special && !sleeping && pct.HasValue && p < 90;    // у доброму настрої для витівок
        bool lonely = chill && !Walking && (Lonely || Force == "lonely");
        bool fun = chill && !lonely;                                      // ти поруч — можна пустувати
        bool shades = fun && (f < CoolUntil || Force == "shades");
        bool coffee = fun && p < 75 && !Walking && (Force == null ? now.Hour >= 8 && now.Hour < 10 : Force == "coffee");
        bool lunch = fun && !Walking && (Force == null ? hm >= 1300 && hm < 1330 : Force == "lunch");
        bool disco = fun && (Force == null ? dow == 5 && now.Hour >= 17 && now.Hour < 20 : Force == "disco");
        bool monday = fun && (Force == null ? dow == 1 && now.Hour >= 8 && now.Hour < 11 : Force == "monday");
        bool hover = fun && Hover;
        bool dance = fun && musicOn;                                        // грає музика — танцює
        int beat = Force == "dance" ? f / 3 : Beat;

        Color body = p >= 90 ? C(204, 92, 77) : p >= 75 ? C(224, 128, 77) : C(217, 120, 87);
        int bobPeriod = party || hover || disco || welcome ? 2 : sleeping || lonely || monday ? 9 : p >= 90 ? 7 : p >= 75 ? 2 : p >= 50 ? 5 : 4;
        bool up = busy || (dance ? beat % 2 == 0 : (f / bobPeriod) % 2 == 0);   // у танці підстрибує в такт
        int y0 = scared ? 4 : 3 + (up ? 0 : 1);            // тіло починається з 3-го рядка; з переляку присідає
        bool blink = f % (p >= 50 ? 36 : 24) < 2;
        string legs = (f / (Walking || held ? 1 : party || disco ? 2 : 3)) % 2 == 1 ? ".X..X.X..X." : "..X.X.X.X..";

        {
            var cv = new Canvas { G = g, K = k, X0 = x0, Y0 = y0px };
            cv.Ox = 1 + (panic || scared ? (f % 2 == 0 ? 1 : -1)      // тремтить
                       : disco ? ((f / 3) % 2 == 0 ? 1 : -1)          // або танцює, гойдаючись
                       : dance ? (beat % 4 < 2 ? 1 : -1) : 0);
            for (int y = 0; y < Rows.Length; y++)
                for (int x = 0; x < Rows[y].Length; x++)
                    if (Rows[y][x] == 'X') cv.Cell(x, y + y0, body);
            for (int x = 0; x < legs.Length; x++) if (legs[x] == 'X') cv.Cell(x, 5 + y0, body);

            int ey = 1 + y0, my = 3 + y0;
            // На масштабі 1× пів-пікселя не намалюєш, тож заплющені очі — просто блідіші.
            Color shut = k == 1 ? Color.FromArgb((Dark.R + body.R) / 2, (Dark.G + body.G) / 2, (Dark.B + body.B) / 2) : Dark;
            Action<int, bool> eyes = (dx, closed) => {
                if (closed) { cv.Cell(3 + dx, ey, shut, 0.4, 0.6); cv.Cell(7 + dx, ey, shut, 0.4, 0.6); }
                else { cv.Cell(3 + dx, ey, Dark); cv.Cell(7 + dx, ey, Dark); }
            };
            Action happyEyes = () => { cv.Cell(3, ey, Dark, 0.5); cv.Cell(7, ey, Dark, 0.5); };   // ^ ^
            Action wideEyes = () => {                                                           // очі з білками
                cv.Cell(2, ey, Color.White); cv.Cell(3, ey, Dark); cv.Cell(6, ey, Color.White); cv.Cell(7, ey, Dark);
            };
            Action smile = () => cv.Cell(5, my, Dark, 0.5, 0.2);
            Action<int> drop = x => cv.Cell(x, 3 + (f / 2 + x) % 5, Teal, fix: true);
            Action<bool, bool> claws = (leftUp, rightUp) => {                                   // підняті клешні
                if (leftUp) { cv.Cell(0, y0 + 1, body); cv.Cell((f / 2) % 2 == 0 ? 0 : -1, y0, body); }
                if (rightUp) { cv.Cell(10, y0 + 1, body); cv.Cell((f / 2) % 2 == 0 ? 10 : 11, y0, body); }
            };
            bool hat = halloween || winter;

            if (fall) {                                       // падає: очі круглі, рот «о», клешні вгору
                wideEyes(); cv.Cell(5, my, Dark); claws(true, true);
            } else if (fly) {                                 // летить на батуті: радіє, клешні вгору
                happyEyes(); smile(); claws(true, true);
            } else if (snipP) {                               // клацає клешнею біля курсора
                eyes(1, false); smile();
                if ((f / 2) % 2 == 0) claws(false, true);
            } else if (held) {                                // у повітрі: очі круглі, рот «о», ноги бовтаються
                wideEyes(); cv.Cell(5, my, Dark);
            } else if (dizzy) {                               // паморочиться: очі заплющені, зірочки кружляють
                eyes(0, true);
                cv.Cell(4, my, Dark, 0.3, 0.5); cv.Cell(5, my, Dark, 0.3, 0.2); cv.Cell(6, my, Dark, 0.3, 0.5);
                int[] ox = { 1, 5, 9, 5 }, oy = { -1, -2, -1, 0 };
                for (int i = 0; i < 2; i++) { int j = (f / 2 + i * 2) % 4; cv.Cell(ox[j], y0 + oy[j] - 1, Star, 0.6); }
            } else if (scared) {                              // чайка над головою: присів, тремтить, клешні над головою
                wideEyes(); cv.Cell(5, my, Dark);
                claws(true, true); drop(11);
            } else if (welcome) {                             // повернувся! махає обома клешнями, над головою сердечко
                happyEyes(); cv.Cell(4, my, Dark, 0.5, 0.2); smile(); cv.Cell(6, my, Dark, 0.5, 0.2);
                claws(true, true);
                cv.Cell(1, ey + 1, Blush, 0.5); cv.Cell(9, ey + 1, Blush, 0.5);
                if (!hat && (f / 3) % 2 == 0) {
                    cv.Cell(4, y0 - 2, Heart); cv.Cell(6, y0 - 2, Heart); cv.Cell(5, y0 - 1, Heart);
                    cv.Cell(4, y0 - 1, Heart, 0.5); cv.Cell(6, y0 - 1, Heart, 0.5);
                }
            } else if (angry) {                               // насуплені брови, дивиться вслід чайці, трясе клешнею
                eyes(-1, false);
                cv.Cell(2, y0, Dark, 0.4, 0.1); cv.Cell(3, y0, Dark, 0.4, 0.5);
                cv.Cell(6, y0, Dark, 0.4, 0.5); cv.Cell(7, y0, Dark, 0.4, 0.1);
                cv.Cell(4, my, Dark, 0.3, 0.4); cv.Cell(5, my, Dark, 0.3, 0.4); cv.Cell(6, my, Dark, 0.3, 0.4);
                claws(false, true);
            } else if (wave) {
                happyEyes();
                smile();
                if ((f / 2) % 2 == 0) { cv.Cell(10, y0 + 1, body); cv.Cell(10, y0, body); }   // права клешня вгору
                else { cv.Cell(10, y0 + 1, body); cv.Cell(11, y0, body); }                     // і похитує
            } else if (party) {
                happyEyes();
                smile();
                for (int i = 0; i < 6; i++)                                                     // конфеті падає
                    cv.Cell((i * 5 + 2) % 13 - 1, (f / 2 + i * 2) % 9, Confetti[i % 5], fix: true);
            } else if (!pct.HasValue) {
                eyes(0, true);
            } else if (sleeping) {
                eyes(0, true);
                for (int z = 0; z <= (f / 6) % 4 && z < 3; z++)                                // zzz піднімається
                    cv.Cell(9 + z, 2 - z % 2 - (z == 2 ? 1 : 0), Zzz, fix: true);
            } else if (panic) {
                wideEyes();
                cv.Cell(5, my, Dark);                                                           // рот "о"
                drop(11); drop(0);
            } else if (p >= 90) {
                eyes(0, true);
                cv.Cell(5, my, Dark, 0.5, 0.3);
                drop(11); drop(0);
            } else if (dance) {                               // танцює під музику: клешні по черзі в такт
                happyEyes(); smile();
                claws(beat % 2 == 0, beat % 2 == 1);
                if (hover) { cv.Cell(1, ey + 1, Blush, 0.5); cv.Cell(9, ey + 1, Blush, 0.5); }
            } else if (lonely) {                              // сумує: дрімає, іноді визирає тебе, сумний рот, сльозинка
                int t = f % 60;
                if (t < 12) eyes((f / 4) % 2 == 0 ? -1 : 1, false); else eyes(0, true);
                cv.Cell(4, my, Dark, 0.3, 0.5); cv.Cell(5, my, Dark, 0.3, 0.2); cv.Cell(6, my, Dark, 0.3, 0.5);
                if (t >= 20 && t < 41) cv.Cell(3, ey + 1 + (t - 20) / 7, Teal, 0.5);
            } else {
                if (shades) {                                                                   // темні окуляри 😎
                    // Скельця 2×1 на місці очей і перенісся; по боках лишається тіло, щоб не злилося з панеллю.
                    cv.Cell(3, ey, Dark); cv.Cell(4, ey, Dark); cv.Cell(6, ey, Dark); cv.Cell(7, ey, Dark);
                    cv.Cell(5, ey, Dark, 0.4);
                    if (k > 1) { cv.Cell(3, ey, Glint, 0.3); cv.Cell(6, ey, Glint, 0.3); }      // відблиск
                } else if (disco || hover) happyEyes();
                else if (p >= 75) eyes(new[] { -1, 0, 1, 0 }[(f / 4) % 4], blink);
                else if (monday) eyes(0, f % 50 >= 8 || f % 50 < 2);                           // ледве розплющує очі
                else if (coffee && f % 40 < 6) eyes(0, true);                                   // смакує ковток
                else eyes(LookDx, blink);

                if (monday && f % 50 < 8) cv.Cell(5, my, Dark, 1);                              // позіхає
                else if (lunch) cv.Cell(5, my, Dark, (f / 3) % 2 == 0 ? 0.6 : 0.25, 0.2);       // жує
                else if (p >= 75) drop(11);
                else if (p >= 50 || hover || shades || disco) smile();
                if (monday) {                                                                   // мішки під очима
                    var bag = Color.FromArgb(body.R * 3 / 4, body.G * 3 / 4, body.B * 3 / 4);
                    cv.Cell(3, ey + 1, bag, 0.3); cv.Cell(7, ey + 1, bag, 0.3);
                }
                if (hover) { cv.Cell(1, ey + 1, Blush, 0.5); cv.Cell(9, ey + 1, Blush, 0.5); }  // червоніє
                if (coffee) {                                                                   // кружка в правій клешні
                    cv.Cell(11, y0 + 1, Coffee, 0.5, 0.5); cv.Cell(12, y0 + 1, Coffee, 0.5, 0.5);
                    cv.Cell(11, y0 + 2, Mug); cv.Cell(12, y0 + 2, Mug);
                    cv.Cell(11, y0 + 3, Mug); cv.Cell(12, y0 + 3, Mug);
                    cv.Cell(11 + (f / 4) % 2, y0 - (f / 4) % 3, Steam, 0.5);                    // пара піднімається
                } else if (lunch) {                                                             // рибка в клешні
                    cv.Cell(11, y0 + 2, Fish); cv.Cell(12, y0 + 2, Fish, 0.6, 0.2);
                    cv.Cell(13, y0 + 1, Fish, 0.6, 0.4); cv.Cell(13, y0 + 2, Fish, 0.6, 0.4);   // хвіст-«ластівка»
                    cv.Cell(11, y0 + 2, Dark, 0.3, 0.2);                                        // око рибки
                }
                if (disco) {                                                                    // дзеркальна куля й вогники
                    hat = false;
                    cv.Cell(5, y0 - 3, C(120, 120, 120), 0.5, 0.5, fix: true);                  // ниточка
                    for (int x = 4; x <= 6; x++)                                                // куля 3×2, грані блищать по черзі
                        for (int y = y0 - 2; y <= y0 - 1; y++)
                            cv.Cell(x, y, (x + y + f / 2) % 3 == 0 ? Color.White : C(150, 155, 170), fix: true);
                    int[] lx = { 0, 12, 1, 11, 6 }, ly = { 1, 2, 8, 9, 0 };
                    for (int i = 0; i < lx.Length; i++)
                        if ((f / 2 + i) % 3 != 0) cv.Cell(lx[i], ly[i], Confetti[(f / 2 + i) % 5], 0.5, fix: true);
                    claws((f / 3) % 2 == 0, (f / 3) % 2 == 1);
                }
            }
            if (halloween && hat) {                                                             // гарбуз на голові
                for (int x = 3; x <= 7; x++) cv.Cell(x, y0 - 1, Pumpkin);
                for (int x = 4; x <= 6; x++) cv.Cell(x, y0 - 2, Pumpkin);
                cv.Cell(4, y0 - 1, Dark, 0.5); cv.Cell(6, y0 - 1, Dark, 0.5);                   // вирізані очі
                cv.Cell(5, y0 - 3, Stem);
            } else if (winter && hat) {                                                         // новорічна шапка
                for (int x = 3; x <= 7; x++) cv.Cell(x, y0 - 1, Color.White);
                for (int x = 4; x <= 6; x++) cv.Cell(x, y0 - 2, Red);
                cv.Cell(5, y0 - 3, Color.White);
            }
            if (flagDay && !hat) {                                                              // синьо-жовтий прапорець
                for (int y = y0 - 3; y <= y0 - 1; y++) cv.Cell(5, y, C(150, 150, 150));
                cv.Cell(6, y0 - 3, C(0, 87, 184)); cv.Cell(7, y0 - 3, C(0, 87, 184));
                cv.Cell(6, y0 - 2, C(255, 213, 0)); cv.Cell(7, y0 - 2, C(255, 213, 0));
            }
            if (valentine && fun && !hat && !flagDay && (f / 4) % 2 == 0) {                     // Валентинка: сердечка над головою
                cv.Cell(4, y0 - 2, Heart); cv.Cell(6, y0 - 2, Heart); cv.Cell(5, y0 - 1, Heart);
                cv.Cell(4, y0 - 1, Heart, 0.5); cv.Cell(6, y0 - 1, Heart, 0.5);
            }
            if (Cyber) {                                                                         // кіберімпланти
                cv.Cell(2, ey, f % 20 < 10 ? C(0, 230, 255) : C(0, 140, 200), 0.5, 0.25);       // світний імплант біля лівого ока
                cv.Cell(0, y0 + 2, C(205, 210, 220), 0.5, 0.5); cv.Cell(10, y0 + 2, C(205, 210, 220), 0.5, 0.5);   // хромовані клешні
            }
        }
    }

    // Іскри біля курсора 12×12 (одиниця u px): «плюс» і «хрестик» навперемін, як на Mac.
    public static void PaintSpark(Graphics g, int x0, int y0, int u, int f) {
        using (var b = new SolidBrush(C(255, 214, 10))) {
            if ((f / 2) % 2 == 0) { g.FillRectangle(b, x0 + 5 * u, y0, 2 * u, 12 * u); g.FillRectangle(b, x0, y0 + 5 * u, 12 * u, 2 * u); }
            else foreach (var p in new[] { new Point(1, 1), new Point(9, 1), new Point(1, 9), new Point(9, 9), new Point(5, 5) })
                g.FillRectangle(b, x0 + p.X * u, y0 + p.Y * u, 2 * u, 2 * u);
        }
    }

    // Батут 13×4 клітинки (як на Mac): синій мат із червоними краями на трьох сірих ніжках.
    // Коли на нього приземлились, мат прогинається посередині.
    public const int TrampW = 13, TrampH = 4;
    public static void PaintTrampoline(Graphics g, int x0, int y0px, int k, bool squash) {
        var cv = new Canvas { G = g, K = k, X0 = x0, Y0 = y0px, Ox = 0 };
        for (int x = 0; x < TrampW; x++) cv.Cell(x, 0, C(60, 110, 230), 0.5, squash ? (x >= 3 && x <= 9 ? 0.7 : 0.3) : 0);
        cv.Cell(0, 0, C(255, 59, 48), 0.5); cv.Cell(12, 0, C(255, 59, 48), 0.5);              // червоні краї
        foreach (int x in new[] { 1, 6, 11 }) for (int y = 1; y <= 3; y++) cv.Cell(x, y, C(130, 130, 140));
    }

    // Чайка 10×7 клітинок, летить ліворуч і махає крилами: угору, рівно, униз, рівно.
    public const int GullW = 10, GullH = 7;
    static readonly string[][] GullFrames = {
        new[] { "......K...", ".....WW...", "....WW....", "OHHBBBBBTT", "..BBBBB...", "..........", ".........." },
        new[] { "..........", "..........", "..........", "OHHBWWWWWK", "..BBBBB...", "..........", ".........." },
        new[] { "..........", "..........", "..........", "OHHBBBBBTT", "..BBBBB...", "....WW....", ".....K...." },
        new[] { "..........", "..........", "..........", "OHHBWWWWWK", "..BBBBB...", "..........", ".........." } };
    // Кажан 10×5 (на Хелловін замість чайки; малюнок — як на Mac): фіолетові крила, червоні очі.
    static readonly string[][] BatFrames = {
        new[] { "W........W", "WW..EE..WW", "WWW.RR.WWW", ".WWBBBBWW.", "....BB...." },
        new[] { "..........", "..........", "WWW.EE.WWW", "WWWWBBWWWW", "..W.BB.W.." },
        new[] { "..........", "..........", "...EBBE...", "WWWBBBBWWW", "WWW.BB.WWW" },
        new[] { "..........", "..........", "WWW.EE.WWW", "WWWWBBWWWW", "..W.BB.W.." } };

    public static void PaintGull(Graphics g, int x0, int y0px, int k, int f, bool bat) {
        var cv = new Canvas { G = g, K = k, X0 = x0, Y0 = y0px, Ox = 0 };
        if (bat) {
            var b = BatFrames[(f / 2) % 4];
            for (int y = 0; y < b.Length; y++)
                for (int x = 0; x < b[y].Length; x++) {
                    char ch = b[y][x];
                    if (ch == 'W') cv.Cell(x, y + 1, C(95, 62, 120));
                    else if (ch == 'B' || ch == 'E') cv.Cell(x, y + 1, C(45, 30, 60));
                    else if (ch == 'R') cv.Cell(x, y + 1, C(255, 60, 60));
                }
            return;
        }
        var rows = GullFrames[(f / 2) % 4];
        for (int y = 0; y < GullH; y++)
            for (int x = 0; x < GullW; x++) {
                char ch = rows[y][x];
                if (ch == 'O') cv.Cell(x, y, C(255, 159, 10), 0.5, 0.3);                       // дзьоб
                else if (ch == 'H' || ch == 'B') cv.Cell(x, y, Color.White);
                else if (ch == 'W') cv.Cell(x, y, C(190, 195, 205));                           // крило
                else if (ch == 'K') cv.Cell(x, y, C(50, 50, 55));                              // темний кінчик крила
                else if (ch == 'T') cv.Cell(x, y, C(160, 165, 170), 0.6);                      // хвіст
            }
        cv.Cell(1, 3, Dark, 0.4, 0.1);                                                          // око
    }

    void Bar(Graphics g, int y, int h, int size, double? pct, double? hot) {
        using (var track = new SolidBrush(LightTaskbar ? C(190, 190, 190) : C(80, 80, 80)))
            g.FillRectangle(track, 0, y, size, h);
        if (!pct.HasValue) return;
        double v = Math.Max(0, Math.Min(100, pct.Value));
        int w = (int)Math.Round(v / 100 * size);
        if (w == 0 && v > 0) w = 1;
        Color c = hot >= 90 ? C(255, 69, 58) : hot >= 70 ? C(255, 159, 10) : LightTaskbar ? C(70, 70, 70) : C(225, 225, 225);
        using (var b = new SolidBrush(c)) g.FillRectangle(b, 0, y, w, h);
    }
}

// Великий краб із цифрами поверх лівого краю панелі задач: у треї Windows не дає іконку, більшу за 16-32 px.
// Це прозоре вікно "завжди зверху"; прозорість по пікселях — через UpdateLayeredWindow.
class TaskbarWidget : Form {
    [DllImport("user32.dll")] static extern IntPtr FindWindow(string cls, string name);
    [DllImport("user32.dll")] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string name);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool UpdateLayeredWindow(IntPtr h, IntPtr dstDC, ref POINT dst, ref SIZE size,
        IntPtr srcDC, ref POINT src, int key, ref BLEND blend, int flags);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPINFOHEADER bi, uint usage, out IntPtr bits, IntPtr section, uint offset);
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    [DllImport("shell32.dll")] static extern IntPtr SHAppBarMessage(int msg, ref APPBARDATA data);
    struct RECT { public int L, T, R, B; }
    struct POINT { public int X, Y; }
    struct SIZE { public int W, H; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] struct BLEND { public byte Op, Flags, Alpha, Format; }
    struct BITMAPINFOHEADER { public int biSize, biWidth, biHeight; public short biPlanes, biBitCount; public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant; }
    struct APPBARDATA { public int cbSize; public IntPtr hWnd; public int uCallbackMessage, uEdge; public RECT rc; public IntPtr lParam; }

    // Шматок тексту: Kind 0 — підпис ("5г"), 1 — звичайна цифра, 2 — від 70%, 3 — від 90%.
    public class Seg {
        public string Text; public int Kind;
        public Seg(string text, int kind) { Text = text; Kind = kind; }
    }

    bool active, fullscreen;
    int barTop, barH, anchorLeft, anchorRight;
    float fontPx;
    Font regular, bold;
    readonly Bitmap probe = new Bitmap(1, 1);
    readonly ToolTip tip = new ToolTip { ShowAlways = true };
    string tipText;

    public TaskbarWidget() {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
    }
    // Шарувате (прозоре), без кнопки в Alt+Tab, не забирає фокус, завжди зверху.
    protected override CreateParams CreateParams {
        get { var cp = base.CreateParams; cp.ExStyle |= 0x80000 | 0x80 | 0x08000000 | 0x8; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }

    // Раз на секунду: де панель задач і чи можна зараз показувати віджет.
    // Повертає false, коли віджет недоречний (вимкнений, панель ховається сама чи стоїть збоку) — тоді краб живе в треї.
    public bool Place(bool wanted) {
        active = false;
        RECT r;
        IntPtr tb = FindWindow("Shell_TrayWnd", null);
        if (!wanted || tb == IntPtr.Zero || !GetWindowRect(tb, out r) || r.R - r.L < r.B - r.T) { Hide(); return false; }
        var abd = new APPBARDATA(); abd.cbSize = Marshal.SizeOf(abd);
        if (((long)SHAppBarMessage(4 /* ABM_GETSTATE */, ref abd) & 1 /* ABS_AUTOHIDE */) != 0) { Hide(); return false; }
        barTop = r.T; barH = r.B - r.T;
        if (IconsLeftAligned()) {   // ліворуч кнопка «Пуск», тому стаємо одразу перед треєм
            RECT n;
            IntPtr tn = FindWindowEx(tb, IntPtr.Zero, "TrayNotifyWnd", null);
            anchorRight = tn != IntPtr.Zero && GetWindowRect(tn, out n) ? n.L : r.R;
            anchorLeft = -1;
        } else anchorLeft = r.L;
        int st;   // 2 — повноекранна програма, 3 — гра, 4 — презентація: не заважаємо
        fullscreen = SHQueryUserNotificationState(out st) == 0 && (st == 2 || st == 3 || st == 4);
        if (fullscreen) Hide();
        active = true;
        return true;
    }

    static bool IconsLeftAligned() {
        using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
            object v = k == null ? null : k.GetValue("TaskbarAl");
            return v is int && (int)v == 0;
        }
    }

    // Де зараз краб: удома, гуляє, у руці, летить після кидка, паморочиться, йде чи летить додому,
    // на батуті, ховається чи ловить курсор.
    enum Mode { Home, Walk, Drag, Fall, Dizzy, Return, FlyHome, Tramp, Hide, Snip, Psycho, Holo }
    Mode mode = Mode.Home;
    int crabX, crabY;                            // лівий верхній кут полотна краба на екрані
    int homeX, homeY, k = 4;
    float s = 1;
    double lastFt;                               // час останнього малювання, у кадрах анімації (дробовий)
    public bool Busy { get { return mode != Mode.Home || gullStart >= 0; } }
    public bool Walking { get { return mode == Mode.Walk; } }
    public string ModeName { get { return mode.ToString(); } }
    public double ThrowVX { get { return fvx; } }
    public Point TextPoint { get { return new Point(menuLeft + homeWidth - (int)(20 * s), barTop + barH / 2); } }
    public Point CrabPoint { get { return new Point(homeX + 7 * k, homeY + 5 * k); } }
    public event Action Clicked;
    public bool Cyber;                           // кіберпанк-режим (пункт меню)
    public double Hot;                           // справжній найвищий ліміт (без поправки −3, яку має настрій краба)

    // Кіберпсихоз: від 95% у кіберпанк-режимі краба «накриває» — він глючить, зникає й телепортується
    // по вільній частині панелі задач 5–7 разів (щоразу 4–8 кадрів, з бірюзовим спалахом), потім вертається додому.
    int[] psX, psEnd;
    double psStart;
    public bool StartPsycho(double ft, BarLayout lay, Random rng) {
        if (anchorLeft < 0 || mode != Mode.Home) return false;
        int right = (lay.StartLeft > homeX ? lay.StartLeft : homeX + (int)(600 * s)) - 14 * k - (int)(10 * s);
        int n = rng.Next(5, 8);
        psX = new int[n + 1]; psEnd = new int[n + 1];
        int t = 0;
        for (int i = 0; i < n; i++) {
            psX[i] = rng.Next(Math.Max(0, homeX - 2 * k), Math.Max(homeX + 1, right));
            t += rng.Next(4, 9); psEnd[i] = t;
        }
        psX[n] = homeX; psEnd[n] = t + 3;                                  // останній стрибок — додому
        psStart = ft; mode = Mode.Psycho;
        return true;
    }

    // Усі сцени — таймлайни в кадрах по 0.15 с, але час дробовий (ft): поки краб у русі, App малює ~30 разів на секунду,
    // і краб рухається плавно, а не «сходинками». Анімація самого краба (ноги, очі) лишається покадровою.

    // Прогулянка: боком вправо з постійною швидкістю, на дальньому кінці роззирається й махає іконкам, потім назад.
    const int Rest = 26;                         // кадрів на дальньому кінці
    int walkEdge, walkDist = -1, walkOut;
    double walkStart, walkPart;

    // edge — екранний X, де починаються іконки панелі (-1, якщо не знайшли); part — яку частину шляху пройти.
    public void StartWalk(double ft, int edge, double part) {
        if (anchorLeft < 0 || mode != Mode.Home) return;   // притулений справа до трею — гуляти нікуди
        mode = Mode.Walk; walkStart = ft; walkEdge = edge; walkPart = part; walkDist = -1;
    }

    // Чайка (на Хелловін — кажан): прилітає згори біля іконок і летить ліворуч за край екрана.
    int gullFrom, angryUntil;
    double gullStart = -1;
    public void StartGull(double ft, int edge) {
        if (anchorLeft < 0 || gullStart >= 0) return;
        gullStart = ft;
        gullFrom = edge > homeX ? edge - (int)(20 * s) : homeX + (int)(600 * s);
    }

    // Батут (ідея з Mac, де краб падає з менюбару на Dock). Тут дім унизу, тож краб вистрибує з дому на батут на «даху»
    // панелі, відскакує, біжить по верхньому краю панелі до кнопки відкритої програми, сідає на її значок,
    // роззирається ~36 с, повертається й летить додому великою дугою. Таймлайн — як на Mac (`trampFrame`).
    int trHX, trHY, trTX, trG, trRoof, trIX, trIconTop, trWalk;
    double trStart;
    bool trSquash;
    public bool StartTramp(double ft, BarLayout lay, Random rng) {
        if (anchorLeft < 0 || mode != Mode.Home || lay.Apps.Count == 0 || lay.StartLeft <= homeX) return false;
        var icon = lay.Apps[rng.Next(lay.Apps.Count)];
        trHX = homeX + 7 * k; trHY = homeY + 9 * k;                     // центр і низ ніг удома
        trRoof = barTop + (int)(2 * s);                                 // ноги на верхньому краї панелі
        trG = trRoof - Crab.TrampH * k;                                 // верх мату
        trIX = icon.X + icon.Width / 2;
        trIconTop = icon.Y + icon.Height / 2 - (int)(12 * s);           // верх значка програми
        // Батут — на вільному місці лівіше «Пуску», за 120–300 px від значка, але не на цифрах.
        int half = Crab.TrampW * k / 2;
        int minX = menuLeft + homeWidth + (int)(30 * s) + half, maxX = lay.StartLeft - (int)(10 * s) - half;
        if (maxX < minX) return false;
        trTX = Math.Max(minX, Math.Min(maxX, trIX - (int)(rng.Next(120, 301) * s)));
        trWalk = Math.Max(8, Math.Abs(trIX - trTX) / (2 * k));
        trStart = ft; mode = Mode.Tramp;
        return true;
    }

    // Де краб у кадр t: центр X, низ ніг Y, поза, чи йде, куди дивиться, чи прогнувся батут. false — сцена скінчилась.
    bool TrampFrame(double t, out int x, out int foot, out string pose, out bool walking, out int look, out bool squash) {
        x = trTX; foot = trG; pose = null; walking = false; look = 0; squash = false;
        int n1 = 12;                                                    // стрибок з дому на батут
        if (t < n1) {
            double u = t / n1;
            x = Lerp(trHX, trTX, u); foot = Lerp(trHY, trG, u) - Arc(120, u); pose = u < 0.5 ? "fly" : "fall";
            return true;
        }
        t -= n1;
        int[] bd = { 10, 8, 6, 4 }, bh = { 170, 100, 55, 25 };          // відскоки, щоразу нижчі
        for (int i = 0; i < bd.Length; i++) {
            if (t < bd[i]) { foot = trG - Arc(bh[i], t / bd[i]); pose = "fly"; squash = t < 1; return true; }
            t -= bd[i];
        }
        int dir = Math.Sign(trIX - trTX);
        if (t < trWalk) { x = Lerp(trTX, trIX, t / trWalk); foot = trRoof; walking = true; look = dir; return true; }
        t -= trWalk;
        if (t < 6) { double u = t / 6.0; x = trIX; foot = Lerp(trRoof, trIconTop, u) - Arc(18, u); return true; }   // застрибує на значок
        t -= 6;
        if (t < 240) { x = trIX; foot = trIconTop; int q = ((int)(t / 25)) % 4; look = q == 1 ? -1 : q == 3 ? 1 : 0; return true; }  // сидить
        t -= 240;
        if (t < 5) { double u = t / 5.0; x = trIX; foot = Lerp(trIconTop, trRoof, u) - Arc(12, u); return true; }
        t -= 5;
        if (t < trWalk) { x = Lerp(trIX, trTX, t / trWalk); foot = trRoof; walking = true; look = -dir; return true; }
        t -= trWalk;
        int[] rd = { 6, 8 }, rh = { 20, 40 };                           // розгойдується перед стартом
        for (int i = 0; i < rd.Length; i++) {
            if (t < rd[i]) { foot = trG - Arc(rh[i], t / rd[i]); pose = "fly"; squash = t < 1; return true; }
            t -= rd[i];
        }
        if (t < 20) {                                                   // запуск додому
            double u = t / 20.0;
            x = Lerp(trTX, trHX, u); foot = Lerp(trG, trHY, u) - Arc(130, u); pose = "fly";
            return true;
        }
        return false;
    }
    static int Lerp(int a, int b, double u) { return a + (int)Math.Round((b - a) * u); }
    int Arc(int height, double u) { return (int)(height * s * 4 * u * (1 - u)); }   // парабола: 0 → height → 0

    // Хованка (на Mac краб ховається у виріз камери; тут — за кнопку «Пуск»): заходить за неї, стоїть,
    // визирає одним оком, ще трохи ховається й виходить додому.
    int hdStartLeft, hdDist, hdOut;
    double hdStart;
    public bool StartHide(double ft, BarLayout lay) {
        if (anchorLeft < 0 || mode != Mode.Home || lay.StartLeft <= homeX + homeWidth) return false;
        // Ховається за сам логотип Windows (кнопка ширша за свій значок: різати по кнопці — краб зникав у повітрі).
        hdStartLeft = lay.StartLeft + lay.StartWidth / 2 - (int)(12 * s);
        hdDist = hdStartLeft - homeX;                                   // тіло (клітинки 1..11) повністю за краєм лого
        hdOut = Math.Max(10, hdDist / (2 * k));
        hdStart = ft; mode = Mode.Hide;
        return true;
    }

    // Ловить курсор (ідея з Mac, `snipFrame`): стрибає до мишки, клацає клешнею біля стрілки (жовті іскри) і стрибає назад.
    // Мишку не рухає. Лише коли курсор далеко від краба (> 200 px) і не надто високо (щоб вікно не росло на весь екран).
    int snHX, snHY, snTX, snTY, snCX, snCY;
    double snStart;
    public bool StartSnip(double ft) {
        if (anchorLeft < 0 || mode != Mode.Home) return false;
        var c = Cursor.Position;
        var scr = Screen.FromPoint(new Point(homeX, barTop)).Bounds;
        snHX = homeX + 7 * k; snHY = homeY + 9 * k;
        double dist = Math.Sqrt((double)(c.X - snHX) * (c.X - snHX) + (double)(c.Y - snHY) * (c.Y - snHY));
        if (!scr.Contains(c) || c.Y < scr.Top + 150 * s || c.Y < barTop - 900 * s || dist < 200 * s) return false;
        snCX = c.X; snCY = c.Y;
        snTX = Math.Max(scr.Left + (int)(20 * s), c.X - (int)(36 * s));  // поруч, ліворуч-нижче від стрілки
        snTY = Math.Min(barTop + barH - (int)(2 * s), c.Y + (int)(22 * s));
        snStart = ft; mode = Mode.Snip;
        return true;
    }
    bool SnipFrame(double t, out int x, out int foot, out string pose, out bool spark) {
        x = snTX; foot = snTY; pose = "snip"; spark = false;
        if (t < 14) { double u = t / 14; x = Lerp(snHX, snTX, u); foot = Lerp(snHY, snTY, u) - Arc(120, u); pose = "fly"; return true; }
        t -= 14;
        if (t < 22) { spark = true; return true; }
        t -= 22;
        if (t < 16) { double u = t / 16; x = Lerp(snTX, snHX, u); foot = Lerp(snTY, snHY, u) - Arc(100, u); pose = "fly"; return true; }
        return false;
    }

    // Що стоїть на панелі задач: де кнопка «Пуск» і кнопки відкритих програм (Edge, Telegram…).
    public class BarLayout { public int StartLeft = -1, StartWidth; public List<Rectangle> Apps = new List<Rectangle>(); }

    // Питаємо Windows через UI Automation (дозволу не треба) — це ~0.1–0.3 с, тому лише перед сценою й не в головному потоці.
    public static BarLayout FindLayout() {
        var lay = new BarLayout();
        try {
            var bar = System.Windows.Automation.AutomationElement.FromHandle(FindWindow("Shell_TrayWnd", null));
            var start = bar.FindFirst(System.Windows.Automation.TreeScope.Descendants, new System.Windows.Automation.PropertyCondition(
                System.Windows.Automation.AutomationElement.AutomationIdProperty, "StartButton"));
            if (start != null) {
                lay.StartLeft = (int)start.Current.BoundingRectangle.Left;
                lay.StartWidth = (int)start.Current.BoundingRectangle.Width;
            }
            var apps = bar.FindAll(System.Windows.Automation.TreeScope.Descendants, new System.Windows.Automation.PropertyCondition(
                System.Windows.Automation.AutomationElement.ClassNameProperty, "Taskbar.TaskListButtonAutomationPeer"));
            foreach (System.Windows.Automation.AutomationElement a in apps) {
                var r = a.Current.BoundingRectangle;
                if (!r.IsEmpty && r.Width > 0) lay.Apps.Add(new Rectangle((int)r.Left, (int)r.Top, (int)r.Width, (int)r.Height));
            }
        } catch { }
        return lay;
    }

    // Мишка: натиснув на крабі й потягнув — краб у руці; відпустив — летить зі швидкістю мишки (кидок); просто клік — меню.
    bool pressed, dragging;
    Point pressAt, grab;
    readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
    readonly List<KeyValuePair<long, Point>> moves = new List<KeyValuePair<long, Point>>();   // останні положення мишки
    double fx, fy, fvx, fvy, physT, flyStart;   // кидок: положення й швидкість (px за кадр 0.15 с)
    int bounces, dizzyUntil, flyX0, flyY0;
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button != MouseButtons.Left) return;
        var c = Cursor.Position;
        pressed = true; dragging = false; pressAt = c;
        bool onCrab = c.X >= crabX && c.X < crabX + 14 * k && c.Y >= crabY && c.Y < crabY + 10 * k;
        grab = onCrab ? new Point(c.X - crabX, c.Y - crabY) : new Point(-1, -1);
        moves.Clear(); moves.Add(new KeyValuePair<long, Point>(clock.ElapsedMilliseconds, c));
        Capture = true;
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        if (!pressed || grab.X < 0) return;
        var c = Cursor.Position;
        moves.Add(new KeyValuePair<long, Point>(clock.ElapsedMilliseconds, c));
        if (moves.Count > 16) moves.RemoveAt(0);
        if (!dragging && Math.Abs(c.X - pressAt.X) + Math.Abs(c.Y - pressAt.Y) > 4) { dragging = true; mode = Mode.Drag; }
        if (dragging) Redraw();                  // між кадрами анімації теж, щоб тягнулось плавно
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        if (!pressed) { if (e.Button == MouseButtons.Right && Clicked != null) Clicked(); return; }
        pressed = false; Capture = false;
        if (dragging) { dragging = false; Throw(); }
        else if (Clicked != null) Clicked();
    }
    // Швидкість кидка — як на Mac: зміщення мишки за останні ~120 мс, v = Δ/dt · 0.15 · 0.6 (px за кадр), не більше ±50.
    void Throw() {
        long now = clock.ElapsedMilliseconds;
        var recent = moves.FindAll(m => now - m.Key <= 120);
        fvx = fvy = 0;
        if (recent.Count >= 2) {
            var a = recent[0]; var b = recent[recent.Count - 1];
            double dt = Math.Max((b.Key - a.Key) / 1000.0, 0.016), lim = 50 * s;
            fvx = Math.Max(-lim, Math.Min(lim, (b.Value.X - a.Value.X) / dt * 0.15 * 0.6));
            fvy = Math.Max(-lim, Math.Min(lim, (b.Value.Y - a.Value.Y) / dt * 0.15 * 0.6));
        }
        fx = crabX; fy = crabY; bounces = 0; physT = lastFt; mode = Mode.Fall;
    }

    // Останні дані для малювання — щоб перемалювати під час перетягування, не чекаючи таймера.
    Crab lastCrab; double? lastPct; List<Seg[]> lastLines; bool lastLight; string lastTip;
    void Redraw() { if (lastCrab != null) Draw(lastCrab, lastPct, lastFt, lastLines, lastLight, lastTip); }

    // Полотно для малювання — одне на весь час (DIB-секція, яку бачать і GDI+, і UpdateLayeredWindow). Росте, коли сцена
    // більша, але не створюється заново щокадру: без нових картинок і копіювань 30 разів на секунду.
    IntPtr surfDC, surfBmp, surfOld, surfBits;
    Bitmap surf;
    int surfW, surfH;
    Bitmap Surface(int w, int h) {
        if (surf != null && w <= surfW && h <= surfH) return surf;
        if (surf != null) { surf.Dispose(); SelectObject(surfDC, surfOld); DeleteObject(surfBmp); DeleteDC(surfDC); }
        surfW = Math.Max(w, surfW) + 64; surfH = Math.Max(h, surfH) + 32;
        var bi = new BITMAPINFOHEADER { biSize = 40, biWidth = surfW, biHeight = -surfH, biPlanes = 1, biBitCount = 32 };   // зверху вниз
        IntPtr screen = GetDC(IntPtr.Zero);
        surfDC = CreateCompatibleDC(screen);
        ReleaseDC(IntPtr.Zero, screen);
        surfBmp = CreateDIBSection(surfDC, ref bi, 0, out surfBits, IntPtr.Zero, 0);
        surfOld = SelectObject(surfDC, surfBmp);
        surf = new Bitmap(surfW, surfH, surfW * 4, PixelFormat.Format32bppPArgb, surfBits);
        return surf;
    }

    public void Draw(Crab crab, double? pct, double ft, List<Seg[]> lines, bool light, string tooltip) {
        lastCrab = crab; lastPct = pct; lastFt = ft; lastLines = lines; lastLight = light; lastTip = tooltip;
        if (!active || fullscreen) return;
        int f = (int)Math.Floor(ft);
        int h = barH;
        s = h / 48f;                                         // 48 px — висота панелі на масштабі 100%
        k = Math.Max(1, (int)(h * 0.7f / 10));               // полотно краба ≈ 70% висоти панелі
        int pad = (int)(8 * s), gap = (int)(6 * s);
        if (fontPx != 12f * s) {
            if (regular != null) { regular.Dispose(); bold.Dispose(); }
            fontPx = 12f * s;
            regular = new Font("Segoe UI", fontPx, FontStyle.Regular, GraphicsUnit.Pixel);
            bold = new Font("Segoe UI", fontPx, FontStyle.Bold, GraphicsUnit.Pixel);
        }
        var fmt = (StringFormat)StringFormat.GenericTypographic.Clone();
        fmt.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
        float textW = 0;
        using (var pg = Graphics.FromImage(probe))
            foreach (var line in lines) {
                float lw = 0;
                foreach (var seg in line) lw += pg.MeasureString(seg.Text, seg.Kind >= 2 ? bold : regular, 1000, fmt).Width;
                textW = Math.Max(textW, lw);
            }
        int homeW = pad + 14 * k + gap + (int)Math.Ceiling(textW) + pad;
        homeWidth = homeW;
        int left = anchorLeft >= 0 ? anchorLeft + pad : anchorRight - homeW - pad;
        menuLeft = left;
        homeX = left + pad; homeY = barTop + Math.Max(0, (h - 10 * k) / 2 - k);   // тіло внизу полотна, тож трохи вгору
        int speed = 2 * k;                                                        // 2 клітинки за кадр
        var cur = Cursor.Position;
        var scr = Screen.FromPoint(new Point(homeX, barTop)).Bounds;

        crab.Walking = crab.Held = crab.Dizzy = crab.Hover = false;
        crab.Pose = null;
        bool spark = false;
        beam = blinkOut = holo = false;
        switch (mode) {
            case Mode.Home:
                crabX = homeX; crabY = homeY;
                crab.Hover = cur.X >= left && cur.X < left + homeW && cur.Y >= barTop && cur.Y < barTop + h;
                int dx = cur.X - (homeX + 8 * k);
                bool near = Math.Abs(cur.Y - (barTop + h / 2)) < 30 * h && Math.Abs(dx) < 300 * s;
                crab.LookDx = !near ? 0 : dx < -6 * k ? -1 : dx > 6 * k ? 1 : 0;
                break;
            case Mode.Walk: {
                if (walkDist < 0) {   // перший кадр: рахуємо маршрут
                    int edge = walkEdge > left ? walkEdge : left + (int)(400 * s);       // іконок не знайшли — 400 px
                    int farthest = edge - (int)(12 * s) - 14 * k - homeX;                // правий край краба біля «Пуску»
                    walkDist = Math.Max(homeW, (int)(farthest * walkPart));              // хоча б за цифри
                    walkOut = Math.Max(10, walkDist / speed);
                }
                double t = ft - walkStart;
                if (t >= 2 * walkOut + Rest) { mode = Mode.Home; crabX = homeX; crabY = homeY; break; }
                crabX = homeX + (int)(t < walkOut ? walkDist * t / walkOut
                                     : t < walkOut + Rest ? walkDist
                                     : walkDist * (2 * walkOut + Rest - t) / walkOut);
                crabY = homeY;
                crab.Walking = t < walkOut || t >= walkOut + Rest;
                crab.LookDx = t < walkOut ? 1 : t >= walkOut + Rest ? -1 : ((int)(t / 5)) % 2 == 0 ? -1 : 1;
                if (t >= walkOut + Rest / 2 && t < walkOut + Rest) crab.WaveUntil = Math.Max(crab.WaveUntil, f + 1);  // махає іконкам
                break;
            }
            case Mode.Drag:                              // у руці: тримаємо за те місце, за яке схопили
                var cs = Screen.FromPoint(cur).Bounds;
                crabX = Math.Max(cs.Left, Math.Min(cs.Right - 14 * k, cur.X - grab.X));
                crabY = Math.Max(barTop - (int)(600 * s), Math.Min(homeY, cur.Y - grab.Y));
                crab.Held = true;
                break;
            case Mode.Fall: {                            // летить після кидка: гравітація, стіни, стеля, до 2 відскоків від панелі
                double dtAll = Math.Max(0, Math.Min(2, ft - physT)), g = 14 * s, ceiling = Math.Max(scr.Top, barTop - 700 * s);
                physT = ft;
                while (dtAll > 1e-9 && mode == Mode.Fall) {   // дрібні кроки, щоб відскоки не залежали від частоти кадрів
                    double dt = Math.Min(0.25, dtAll); dtAll -= dt;
                    fvy += g * dt; fx += fvx * dt; fy += fvy * dt;
                    if (fx < scr.Left) { fx = scr.Left; fvx = -fvx * 0.6; }
                    if (fx + 14 * k > scr.Right) { fx = scr.Right - 14 * k; fvx = -fvx * 0.6; }
                    if (fy < ceiling) { fy = ceiling; fvy = Math.Abs(fvy) * 0.4; }
                    if (fy >= homeY) {
                        fy = homeY;
                        if (Math.Abs(fvy) < 30 * s || bounces >= 2) { mode = Mode.Dizzy; dizzyUntil = f + 20; fvx = fvy = 0; }
                        else { fvy = -fvy * 0.5; fvx *= 0.7; bounces++; }
                    }
                }
                crabX = (int)fx; crabY = (int)fy;
                crab.Held = mode == Mode.Fall;
                break;
            }
            case Mode.Dizzy:                             // паморочиться ~3 с, потім додому: близько — пішки, далеко — летить
                crabY = homeY; crab.Dizzy = true;
                if (f >= dizzyUntil) {
                    if (Cyber) { mode = Mode.Holo; flyStart = ft; }            // кіберкраб: голограмою «телепортується» додому
                    else if (Math.Abs(crabX - homeX) > 300 * s) { mode = Mode.FlyHome; flyStart = ft; flyX0 = crabX; flyY0 = crabY; }
                    else { mode = Mode.Return; physT = ft; }
                }
                break;
            case Mode.Return: {                          // дріботить додому
                double step = speed * Math.Max(0, Math.Min(2, ft - physT));
                physT = ft;
                crabY = homeY;
                crabX += Math.Sign(homeX - crabX) * (int)Math.Min(Math.Ceiling(step), Math.Abs(homeX - crabX));
                if (crabX == homeX) mode = Mode.Home;
                crab.Walking = true; crab.LookDx = Math.Sign(homeX - crabX);
                break;
            }
            case Mode.FlyHome: {                         // летить додому дугою за 20 кадрів (як на Mac)
                double u = Math.Min(1, (ft - flyStart) / 20);
                crabX = Lerp(flyX0, homeX, u); crabY = Lerp(flyY0, homeY, u) - Arc(100, u);
                crab.Pose = "fly";
                if (u >= 1) { mode = Mode.Home; crab.Pose = null; }
                break;
            }
            case Mode.Tramp: {
                int px, pf, lk; string pose; bool wk, sq;
                if (!TrampFrame(ft - trStart, out px, out pf, out pose, out wk, out lk, out sq)) {
                    mode = Mode.Home; crabX = homeX; crabY = homeY; break;
                }
                crabX = px - 7 * k; crabY = pf - 9 * k;                  // з центру й низу ніг — у кут полотна
                crab.Pose = pose; crab.Walking = wk; crab.LookDx = lk; trSquash = sq;
                break;
            }
            case Mode.Hide: {
                // Заходить за «Пуск», стоїть 45 кадрів, визирає (видно клешню, око й пів рота) 16 кадрів,
                // ховається ще на 10 і виходить додому.
                double th = ft - hdStart;
                int peek = hdStartLeft - 8 * k - homeX, hx = hdDist;
                crabY = homeY;
                if (th < hdOut) { hx = (int)(hdDist * th / hdOut); crab.Walking = true; crab.LookDx = 1; }
                else if ((th -= hdOut) < 45) { }
                else if ((th -= 45) < 4) hx = Lerp(hdDist, peek, th / 4.0);
                else if ((th -= 4) < 16) { hx = peek; crab.LookDx = -1; }
                else if ((th -= 16) < 4) hx = Lerp(peek, hdDist, th / 4.0);
                else if ((th -= 4) < 10) { }
                else if ((th -= 10) < hdOut) { hx = hdDist - (int)(hdDist * th / hdOut); crab.Walking = true; crab.LookDx = -1; }
                else { mode = Mode.Home; hx = 0; }
                crabX = homeX + hx;
                break;
            }
            case Mode.Holo: {                            // мерехтить голограмою на місці, потім спалах — і вже вдома
                double t = ft - flyStart;
                crabY = homeY;
                holo = t < 10;
                if (t >= 10) { crabX = homeX; beam = t < 11.5; }
                if (t >= 11.5) mode = Mode.Home;
                break;
            }
            case Mode.Psycho: {
                double t = ft - psStart;
                int i = 0;
                while (i < psEnd.Length && t >= psEnd[i]) i++;
                if (i >= psEnd.Length) { mode = Mode.Home; crabX = homeX; crabY = homeY; break; }
                double since = t - (i == 0 ? 0 : psEnd[i - 1]);
                crabX = psX[i]; crabY = homeY;
                crab.Pose = "psycho";
                beam = since < 1.2;                                        // щойно телепортувався — спалах
                blinkOut = psEnd[i] - t < 0.6 && i < psEnd.Length - 1;      // за мить до стрибка зникає
                break;
            }
            case Mode.Snip: {
                int px, pf; string pose;
                if (!SnipFrame(ft - snStart, out px, out pf, out pose, out spark)) { mode = Mode.Home; crabX = homeX; crabY = homeY; break; }
                crabX = px - 7 * k; crabY = pf - 9 * k; crab.Pose = pose; crab.LookDx = 1;
                break;
            }
        }

        // Чайка (на Хелловін — кажан): летить ліворуч на 4 клітинки за кадр. Коли над крабом — він лякається, потім сердиться.
        int gx = 0, gy = 0;
        bool gull = gullStart >= 0;
        crab.Scared = false;
        int gk = k + 1;                          // чайка більша за краба
        if (gull) {
            double t = ft - gullStart;
            gx = gullFrom - (int)(t * 4 * k);
            // Злітає згори, далі летить трохи вище панелі, ледь погойдуючись.
            gy = barTop - (int)(14 * s) - (int)Math.Max(0, 50 * s - t * 3 * k) + (int)(Math.Sin(t / 2.0) * 3 * s);
            int gc = gx + Crab.GullW * gk / 2, cc = crabX + 7 * k;
            if (gc < cc - 40 * s) angryUntil = f + 22;
            else if (gc - cc < 160 * s) crab.Scared = true;
            if (gx + Crab.GullW * gk < scr.Left) gullStart = -1;
        }
        crab.Angry = f < angryUntil;

        // Вікно охоплює «дім», краба, чайку, батут, іскри й сніг. Майже невидимий фон лише вдома, щоб клік ловився по всьому
        // віджету; решта повністю прозора — клік по порожній панелі проходить наскрізь.
        // Неоновий слід (кіберпанк-режим): поки краб рухається, запам'ятовуємо, де він був; удома слід поступово тане.
        bool moving = mode != Mode.Home && mode != Mode.Dizzy && mode != Mode.Psycho && mode != Mode.Holo && mode != Mode.Hide;
        if (Cyber && moving) {
            var last = trail.Count > 0 ? trail[trail.Count - 1] : new Point(-99999, 0);
            if (Math.Abs(last.X - crabX) + Math.Abs(last.Y - crabY) >= 6 * s) { trail.Add(new Point(crabX, crabY)); if (trail.Count > 6) trail.RemoveAt(0); }
        } else if (trail.Count > 0) trail.RemoveAt(0);
        var area = new Rectangle(left, barTop, homeW, h);
        area = Rectangle.Union(area, new Rectangle(crabX, crabY, 14 * k, 10 * k));
        foreach (var tp in trail) area = Rectangle.Union(area, new Rectangle(tp.X - k, tp.Y - 2 * k, 16 * k, 12 * k));
        if (gull) area = Rectangle.Union(area, new Rectangle(gx, gy, Crab.GullW * gk, Crab.GullH * gk));
        bool tramp = mode == Mode.Tramp;
        var trRect = new Rectangle(trTX - Crab.TrampW * k / 2, trG, Crab.TrampW * k, Crab.TrampH * k);
        if (tramp) area = Rectangle.Union(area, trRect);
        int sp = (int)Math.Round(s);
        var spRect = new Rectangle(snCX - 4 * sp, snCY - 2 * sp, 12 * sp, 12 * sp);
        if (spark) area = Rectangle.Union(area, spRect);
        bool snow = crab.Winter && Busy;          // узимку під час сцен іде сніг (удома — ні, щоб не їсти процесор)
        Rectangle snowBand = Rectangle.Empty;
        if (snow) {
            snowBand = Rectangle.FromLTRB(left, Math.Min(area.Top, barTop - (int)(300 * s)), Math.Max(area.Right, left + (int)(600 * s)), barTop + h);
            area = Rectangle.Union(area, snowBand);
        }
        int ox = area.X, oy = area.Y;
        // Глітч (кіберпанк-режим, від 95% або під час кіберпсихозу): кадр «зламаний» приблизно в половині випадків.
        // Випадковість залежить лише від номера кадру, тож між кадрами анімації картинка не стрибає.
        bool glitch = Cyber && (Hot >= 95 || mode == Mode.Psycho);
        var gr = new Random(f * 7919 + 17);
        bool hit = glitch && (gr.NextDouble() < 0.45 || beam);
        var bmp = Surface(area.Width, area.Height);
        using (var g = Graphics.FromImage(bmp)) {
            g.SetClip(new Rectangle(0, 0, area.Width, area.Height));
            g.CompositingMode = CompositingMode.SourceCopy;           // стираємо минулий кадр
            using (var clear = new SolidBrush(Color.Transparent)) g.FillRectangle(clear, 0, 0, area.Width, area.Height);
            using (var catcher = new SolidBrush(Color.FromArgb(1, 0, 0, 0))) g.FillRectangle(catcher, left - ox, barTop - oy, homeW, h);
            g.CompositingMode = CompositingMode.SourceOver;
            if (snow)
                using (var flake = new SolidBrush(Color.White))
                    for (int i = 0; i < 36; i++) {
                        int x = snowBand.X + (i * 197) % Math.Max(1, snowBand.Width) + (int)(Math.Sin((ft + i * 7) / 6) * 10 * s);
                        int y = snowBand.Y + (int)((ft * 7 * s + i * 61) % Math.Max(1, snowBand.Height));
                        g.FillRectangle(flake, x - ox, y - oy, 3 * sp, 3 * sp);
                    }
            // Кібер-дискотека: поки грає музика, за крабом стрибають неонові стовпчики еквалайзера.
            float mus = crab.Force == "dance" ? 0.5f + 0.4f * (float)Math.Abs(Math.Sin(f * 0.7)) : crab.Music;
            if (Cyber && mus > 0 && mode == Mode.Home) {
                var er = new Random(f * 31 + 7);
                int bars = 7, bw = Math.Max(2, 14 * k / (bars * 2 - 1)), bottom = barTop + h - oy - (int)(3 * s);
                for (int i = 0; i < bars; i++) {
                    int hgt = (int)((h - 8 * s) * Math.Min(1.0, mus * (0.45 + er.NextDouble() * 0.8)));
                    float u = i / (float)(bars - 1);
                    using (var b = new SolidBrush(Color.FromArgb(120, (int)(Neon1.R + (Neon2.R - Neon1.R) * u), (int)(Neon1.G + (Neon2.G - Neon1.G) * u), (int)(Neon1.B + (Neon2.B - Neon1.B) * u))))
                        g.FillRectangle(b, homeX - ox + i * 2 * bw, bottom - hgt, bw, hgt);
                }
            }
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            float lineH = regular.GetHeight(), ty = barTop - oy + (h - lines.Count * lineH) / 2;
            foreach (var line in lines) {
                float x = left - ox + pad + 14 * k + gap;
                foreach (var seg in line) {
                    var font = seg.Kind >= 2 ? bold : regular;
                    var col = TextColor(seg.Kind, light);
                    float jx = 0;
                    if (hit && seg.Kind >= 1) { col = gr.Next(2) == 0 ? Neon1 : Neon2; jx = gr.Next(-2, 3) * s; }   // цифри смикаються
                    using (var b = new SolidBrush(col)) g.DrawString(seg.Text, font, b, x + jx, ty, fmt);
                    x += g.MeasureString(seg.Text, font, 1000, fmt).Width;
                }
                ty += lineH;
            }
            if (tramp) Crab.PaintTrampoline(g, trRect.X - ox, trRect.Y - oy, k, trSquash);
            // Краб малюється після тексту: на прогулянці пробігає поверх цифр. У хованці — обрізаний по краю «Пуску».
            if (mode == Mode.Hide) g.SetClip(new Rectangle(0, 0, Math.Max(0, hdStartLeft - ox), area.Height));
            if (Cyber) DrawCyberCrab(g, crab, crabX - ox, crabY - oy, pct, f, gr, glitch, hit, ox, oy);
            else crab.Paint(g, crabX - ox, crabY - oy, k, pct, f);
            g.SetClip(new Rectangle(0, 0, area.Width, area.Height));
            if (spark) Crab.PaintSpark(g, spRect.X - ox, spRect.Y - oy, sp, f);
            if (gull) Crab.PaintGull(g, gx - ox, gy - oy, gk, f, crab.Halloween);
        }
        if (!Visible) Show();
        Push(area.Width, area.Height, ox, oy);
        fmt.Dispose();
        // Панель задач після кліку по ній вилазить нагору, тож щоразу повертаємо віджет поверх неї.
        SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x1 | 0x2 | 0x10);
        if (tooltip != tipText) { tipText = tooltip; tip.SetToolTip(this, tooltip); }
    }
    int menuLeft, homeWidth;
    bool beam, blinkOut;

    // Неонові кольори кіберпанку.
    static readonly Color Neon1 = Color.FromArgb(255, 0, 230, 255), Neon2 = Color.FromArgb(255, 255, 40, 160);

    // Кіберкраб: малюємо краба в маленьку картинку, а тоді кладемо її на полотно по-різному.
    //  - звичайно: під ним рожеве неонове світіння (копія, зсунута на піксель у 4 боки);
    //  - позаду — неоновий слід, що тане (бірюзові копії там, де краб щойно був);
    //  - глітч: червона й бірюзова копії зі зсувом, смуги вбік, «биті пікселі», іноді зникає на мить;
    //  - голограма: синя напівпрозора з рядками-сканлайнами, мерехтить;
    //  - промінь телепорту — бірюзова вертикальна смуга.
    Bitmap crabBmp;
    ImageAttributes redCopy, cyanCopy, glowCopy, holoCopy;
    ImageAttributes[] trailCopy;
    readonly List<Point> trail = new List<Point>();
    bool holo;
    void DrawCyberCrab(Graphics g, Crab crab, int x, int y, double? pct, int f, Random gr, bool glitch, bool hit, int ox, int oy) {
        int cw = 16 * k, ch = 12 * k;                                   // із запасом: клешні й шапка виходять за 14×10
        if (crabBmp == null || crabBmp.Width != cw || crabBmp.Height != ch) {
            if (crabBmp != null) crabBmp.Dispose();
            crabBmp = new Bitmap(cw, ch, PixelFormat.Format32bppPArgb);
            redCopy = Tint(1, 0.15f, 0.25f, 0.75f); cyanCopy = Tint(0, 0.9f, 1, 0.75f);
            glowCopy = Tint(1, 0.16f, 0.63f, 0.35f); holoCopy = Tint(0.35f, 0.8f, 1, 0.6f);
            trailCopy = new ImageAttributes[6];
            for (int i = 0; i < 6; i++) trailCopy[i] = Tint(0, 0.9f, 1, 0.06f + 0.05f * i);
        }
        using (var cg = Graphics.FromImage(crabBmp)) { cg.Clear(Color.Transparent); crab.Paint(cg, k, 2 * k, k, pct, f); }
        int dx = x - k, dy = y - 2 * k, sp = Math.Max(1, (int)Math.Round(2 * s)), px = Math.Max(1, (int)Math.Round(s));
        for (int i = 0; i < trail.Count; i++)                            // неоновий слід, старіші — прозоріші
            g.DrawImage(crabBmp, new Rectangle(trail[i].X - ox - k, trail[i].Y - oy - 2 * k, cw, ch), 0, 0, cw, ch, GraphicsUnit.Pixel, trailCopy[6 - trail.Count + i]);
        if (beam)                                                        // промінь телепорту
            using (var b = new SolidBrush(Color.FromArgb(170, Neon1))) g.FillRectangle(b, x + 6 * k, y - 8 * k, 2 * sp, 18 * k);
        if (holo) {                                                      // голограма зі сканлайнами
            if (f % 5 == 0) return;                                      // мерехтить
            g.DrawImage(crabBmp, new Rectangle(dx, dy, cw, ch), 0, 0, cw, ch, GraphicsUnit.Pixel, holoCopy);
            var mode0 = g.CompositingMode;
            g.CompositingMode = CompositingMode.SourceCopy;
            using (var clear = new SolidBrush(Color.Transparent))
                for (int yy = dy + (f % 3) * px; yy < dy + ch; yy += 3 * px) g.FillRectangle(clear, dx, yy, cw, px);
            g.CompositingMode = mode0;
            return;
        }
        if (!glitch) {
            foreach (var o in new[] { new Point(-1, 0), new Point(1, 0), new Point(0, -1), new Point(0, 1) })
                g.DrawImage(crabBmp, new Rectangle(dx + o.X * sp, dy + o.Y * sp, cw, ch), 0, 0, cw, ch, GraphicsUnit.Pixel, glowCopy);
            g.DrawImage(crabBmp, dx, dy);
            return;
        }
        if (blinkOut || (hit && gr.NextDouble() < 0.12)) return;         // зник на мить
        if (!hit) { g.DrawImage(crabBmp, dx, dy); return; }
        g.DrawImage(crabBmp, new Rectangle(dx - sp * gr.Next(1, 3), dy, cw, ch), 0, 0, cw, ch, GraphicsUnit.Pixel, redCopy);
        g.DrawImage(crabBmp, new Rectangle(dx + sp * gr.Next(1, 3), dy, cw, ch), 0, 0, cw, ch, GraphicsUnit.Pixel, cyanCopy);
        // Основний краб — смугами, частина смуг зсунута вбік.
        int bands = 4, bh = ch / bands;
        for (int i = 0; i < bands; i++) {
            int shift = gr.NextDouble() < 0.5 ? gr.Next(-3, 4) * sp : 0;
            g.DrawImage(crabBmp, new Rectangle(dx + shift, dy + i * bh, cw, bh), new Rectangle(0, i * bh, cw, bh), GraphicsUnit.Pixel);
        }
        for (int i = 0; i < 4; i++)                                      // «биті пікселі»
            using (var b = new SolidBrush(gr.Next(2) == 0 ? Neon1 : Neon2))
                g.FillRectangle(b, dx + gr.Next(cw), dy + gr.Next(ch), gr.Next(1, 4) * sp, sp);
    }
    static ImageAttributes Tint(float r, float gC, float b, float a) {
        var m = new ColorMatrix(new[] {
            new[] { r, 0f, 0f, 0f, 0f }, new[] { 0f, gC, 0f, 0f, 0f }, new[] { 0f, 0f, b, 0f, 0f },
            new[] { 0f, 0f, 0f, a, 0f }, new[] { 0f, 0f, 0f, 0f, 1f } });
        var ia = new ImageAttributes(); ia.SetColorMatrix(m);
        return ia;
    }

    static Color TextColor(int kind, bool light) {
        switch (kind) {
            case 0: return light ? Color.FromArgb(90, 90, 90) : Color.FromArgb(170, 170, 170);
            case 2: return light ? Color.FromArgb(200, 110, 0) : Color.FromArgb(255, 159, 10);
            case 3: return light ? Color.FromArgb(200, 30, 30) : Color.FromArgb(255, 69, 58);
            default: return light ? Color.FromArgb(20, 20, 20) : Color.FromArgb(240, 240, 240);
        }
    }

    // Меню над крабом, лівим краєм по віджету. Фокус беремо, щоб меню закривалось кліком деінде.
    public void ShowMenu(ContextMenuStrip m) {
        SetForegroundWindow(Handle);
        m.Show(new Point(menuLeft, barTop), ToolStripDropDownDirection.AboveRight);
    }

    // Показує лівий верхній кут полотна розміром w×h у точці (x, y) екрана.
    void Push(int w, int h, int x, int y) {
        IntPtr screen = GetDC(IntPtr.Zero);
        var dst = new POINT { X = x, Y = y }; var src = new POINT(); var size = new SIZE { W = w, H = h };
        var blend = new BLEND { Alpha = 255, Format = 1 /* AC_SRC_ALPHA */ };
        UpdateLayeredWindow(Handle, screen, ref dst, ref size, surfDC, ref src, 0, ref blend, 2 /* ULW_ALPHA */);
        ReleaseDC(IntPtr.Zero, screen);
    }
}

class Sample { public DateTime T; public double? S, W; }   // момент (UTC), сесія і тиждень у відсотках

// Історія для графіка: рядок "час;сесія;тиждень" на кожне вдале оновлення (раз на 5 хв). Тримаємо ~30 днів.
static class History {
    static string FilePath { get { return Path.Combine(App.Dir, "history.csv"); } }

    public static void Add(DateTime t, Usage u) {
        try {
            Directory.CreateDirectory(App.Dir);
            File.AppendAllText(FilePath, t.ToString("o") + ";" + Num(u.Session) + ";" + Num(u.Weekly) + "\n");
            if (new FileInfo(FilePath).Length > 600 * 1024) {   // ≈ 50 днів: обрізаємо до останніх 30
                var keep = new List<string>();
                foreach (var p in Load(t.AddDays(-30))) keep.Add(p.T.ToString("o") + ";" + Str(p.S) + ";" + Str(p.W));
                File.WriteAllLines(FilePath, keep);
            }
        } catch { }
    }

    public static List<Sample> Load(DateTime since) {
        var list = new List<Sample>();
        try {
            foreach (var line in File.ReadAllLines(FilePath)) {
                var parts = line.Split(';');
                DateTime t;
                if (parts.Length < 3 || !DateTime.TryParse(parts[0], CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out t)) continue;
                t = t.ToUniversalTime();
                if (t >= since) list.Add(new Sample { T = t, S = Parse(parts[1]), W = Parse(parts[2]) });
            }
        } catch { }
        return list;
    }

    static string Num(Limit l) { return l == null ? "" : Str(l.Percent); }
    static string Str(double? v) { return v.HasValue ? v.Value.ToString(CultureInfo.InvariantCulture) : ""; }
    static double? Parse(string s) {
        double v;
        return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? (double?)v : null;
    }
}

// Вікно з графіком: сесія і тиждень за 24 години або 7 днів. На кінці лінії сесії сидить краб.
class GraphForm : Form {
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

    static Color C(int r, int g, int b) { return Color.FromArgb(r, g, b); }
    static readonly Color Bg = C(32, 32, 32), GridC = C(58, 58, 58), TextC = C(220, 220, 220), Dim = C(140, 140, 140);
    static readonly Color SessionC = C(217, 120, 87), WeekC = C(100, 170, 255);
    static readonly string[] Days = { "Нд", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб" };

    List<Sample> data;
    bool week;                 // false — 24 години, true — 7 днів
    int hoverX = -1, frame;
    readonly float s;          // масштаб екрана (1.25 на 125%)
    readonly Crab crab = new Crab();
    readonly Font font, small;
    readonly System.Windows.Forms.Timer anim = new System.Windows.Forms.Timer { Interval = 150 };
    Rectangle plot, tabDay, tabWeek;
    IntPtr iconHandle;

    public GraphForm(List<Sample> data) {
        this.data = data;
        Text = "Claude Limits · історія";
        BackColor = Bg;
        DoubleBuffered = true;
        StartPosition = FormStartPosition.CenterScreen;
        using (var g = CreateGraphics()) s = g.DpiX / 96f;
        ClientSize = new Size((int)(820 * s), (int)(440 * s));
        MinimumSize = new Size((int)(520 * s), (int)(320 * s));
        font = new Font("Segoe UI", 13 * s, GraphicsUnit.Pixel);
        small = new Font("Segoe UI", 11 * s, GraphicsUnit.Pixel);
        using (var bmp = new Bitmap(32, 32)) {                  // іконка вікна — наш краб
            using (var g = Graphics.FromImage(bmp)) crab.Paint(g, 2, 2, 2, 20, 0);
            iconHandle = bmp.GetHicon();
            Icon = Icon.FromHandle(iconHandle);
        }
        anim.Tick += (o, e) => { frame++; Invalidate(); };
        anim.Start();
        FormClosed += (o, e) => { anim.Dispose(); font.Dispose(); small.Dispose(); DestroyIcon(iconHandle); };
    }

    public void SetData(List<Sample> d) { data = d; Invalidate(); }

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        int dark = 1;
        DwmSetWindowAttribute(Handle, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, ref dark, 4);   // темний заголовок вікна
    }
    protected override void OnMouseMove(MouseEventArgs e) { hoverX = plot.Contains(e.Location) ? e.X : -1; }
    protected override void OnMouseLeave(EventArgs e) { hoverX = -1; }
    protected override void OnMouseUp(MouseEventArgs e) {
        if (tabDay.Contains(e.Location)) week = false;
        else if (tabWeek.Contains(e.Location)) week = true;
        Invalidate();
    }
    protected override void OnResize(EventArgs e) { base.OnResize(e); Invalidate(); }
    protected override void OnPaint(PaintEventArgs e) { Draw(e.Graphics, ClientSize.Width, ClientSize.Height); }

    public void Draw(Graphics g, int W, int H) {
        g.Clear(Bg);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        int m = (int)(16 * s);

        // Вкладки й легенда
        tabDay = Chip(g, "24 години", m, m, !week);
        tabWeek = Chip(g, "7 днів", tabDay.Right + (int)(8 * s), m, week);
        float lx = W - m;
        lx = Legend(g, "Тиждень", WeekC, lx, tabDay.Top + tabDay.Height / 2);
        Legend(g, "Сесія 5 год", SessionC, lx - 16 * s, tabDay.Top + tabDay.Height / 2);

        plot = Rectangle.FromLTRB((int)(52 * s), tabDay.Bottom + (int)(20 * s), W - (int)(28 * s), H - (int)(34 * s));
        DateTime to = DateTime.UtcNow, from = to.AddHours(week ? -168 : -24);
        Func<DateTime, float> X = t => plot.Left + (float)((t - from).TotalSeconds / (to - from).TotalSeconds) * plot.Width;
        Func<double, float> Y = v => plot.Bottom - (float)(Math.Max(0, Math.Min(100, v)) / 100) * plot.Height;

        // Сітка: 0–100% і вертикальні позначки часу
        using (var grid = new Pen(GridC, 1))
        using (var dim = new SolidBrush(Dim)) {
            var right = new StringFormat { Alignment = StringAlignment.Far, LineAlignment = StringAlignment.Center };
            var center = new StringFormat { Alignment = StringAlignment.Center };
            for (int v = 0; v <= 100; v += 25) {
                g.DrawLine(grid, plot.Left, Y(v), plot.Right, Y(v));
                g.DrawString(v + "%", small, dim, plot.Left - 6 * s, Y(v), right);
            }
            DateTime lf = from.ToLocalTime(), t;
            if (week) t = lf.Date.AddDays(1);
            else t = new DateTime(lf.Year, lf.Month, lf.Day, lf.Hour - lf.Hour % 3, 0, 0, DateTimeKind.Local).AddHours(3);
            for (; t.ToUniversalTime() < to; t = week ? t.AddDays(1) : t.AddHours(3)) {
                float x = X(t.ToUniversalTime());
                g.DrawLine(grid, x, plot.Top, x, plot.Bottom);
                g.DrawString(week ? Days[(int)t.DayOfWeek] + " " + t.Day : t.ToString("HH:mm"), small, dim, x, plot.Bottom + 6 * s, center);
            }
        }
        Threshold(g, 70, C(255, 159, 10), Y);
        Threshold(g, 90, C(255, 69, 58), Y);

        var pts = data.FindAll(p => p.T >= from);
        if (pts.Count == 0) {
            using (var b = new SolidBrush(Dim))
                g.DrawString("Історія тільки почала збиратися: нова точка з'являється з кожним оновленням (раз на 5 хв).",
                    font, b, new RectangleF(plot.Left, plot.Top, plot.Width, plot.Height),
                    new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center });
            return;
        }
        Series(g, pts, p => p.W, WeekC, false, X, Y);
        Series(g, pts, p => p.S, SessionC, true, X, Y);

        // Краб сидить на останній точці сесії й підстрибує
        var last = pts.FindLast(p => p.S.HasValue);
        if (last != null) {
            int k = Math.Max(2, (int)(3 * s));
            double mood = Math.Max(last.S.Value - 3, last.W ?? 0);
            g.SmoothingMode = SmoothingMode.None;
            crab.Paint(g, (int)X(last.T) - 7 * k, (int)Y(last.S.Value) - 9 * k, k, mood, frame);
            g.SmoothingMode = SmoothingMode.AntiAlias;
        }
        if (hoverX >= 0) Readout(g, pts, X, Y);
    }

    Rectangle Chip(Graphics g, string text, int x, int y, bool on) {
        var size = g.MeasureString(text, font);
        var r = new Rectangle(x, y, (int)(size.Width + 20 * s), (int)(size.Height + 10 * s));
        using (var path = Rounded(r, (int)(r.Height / 2)))
        using (var fill = new SolidBrush(on ? C(70, 70, 70) : Bg))
        using (var pen = new Pen(on ? C(70, 70, 70) : GridC)) { g.FillPath(fill, path); g.DrawPath(pen, path); }
        using (var b = new SolidBrush(on ? Color.White : Dim))
            g.DrawString(text, font, b, r, new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center });
        return r;
    }

    float Legend(Graphics g, string text, Color c, float right, float cy) {
        float w = g.MeasureString(text, small).Width;
        using (var b = new SolidBrush(TextC)) g.DrawString(text, small, b, right - w, cy - small.Height / 2f);
        using (var p = new Pen(c, 3 * s)) g.DrawLine(p, right - w - 22 * s, cy, right - w - 6 * s, cy);
        return right - w - 22 * s;
    }

    void Threshold(Graphics g, double v, Color c, Func<double, float> Y) {
        using (var p = new Pen(Color.FromArgb(110, c), 1) { DashStyle = DashStyle.Dash })
            g.DrawLine(p, plot.Left, Y(v), plot.Right, Y(v));
    }

    // Лінія з розривами там, де програма не працювала довше 20 хв; під сесією — напівпрозора заливка.
    void Series(Graphics g, List<Sample> pts, Func<Sample, double?> val, Color c, bool fill,
                Func<DateTime, float> X, Func<double, float> Y) {
        var run = new List<PointF>();
        DateTime prev = DateTime.MinValue;
        Action flush = () => {
            if (run.Count > 1) {
                if (fill) {
                    var poly = new List<PointF>(run);
                    poly.Add(new PointF(run[run.Count - 1].X, plot.Bottom));
                    poly.Add(new PointF(run[0].X, plot.Bottom));
                    using (var b = new SolidBrush(Color.FromArgb(45, c))) g.FillPolygon(b, poly.ToArray());
                }
                using (var p = new Pen(c, 2 * s) { LineJoin = LineJoin.Round }) g.DrawLines(p, run.ToArray());
            } else if (run.Count == 1)
                using (var b = new SolidBrush(c)) g.FillEllipse(b, run[0].X - 2 * s, run[0].Y - 2 * s, 4 * s, 4 * s);
            run.Clear();
        };
        foreach (var p in pts) {
            double? v = val(p);
            if (!v.HasValue) continue;
            if (run.Count > 0 && (p.T - prev).TotalMinutes > 20) flush();
            run.Add(new PointF(X(p.T), Y(v.Value)));
            prev = p.T;
        }
        flush();
    }

    // Підказка під мишкою: найближча точка, її час і значення.
    void Readout(Graphics g, List<Sample> pts, Func<DateTime, float> X, Func<double, float> Y) {
        Sample best = null; float bestD = float.MaxValue;
        foreach (var p in pts) { float d = Math.Abs(X(p.T) - hoverX); if (d < bestD) { bestD = d; best = p; } }
        if (best == null) return;
        float x = X(best.T);
        using (var p = new Pen(C(120, 120, 120), 1)) g.DrawLine(p, x, plot.Top, x, plot.Bottom);
        if (best.W.HasValue) using (var b = new SolidBrush(WeekC)) g.FillEllipse(b, x - 4 * s, Y(best.W.Value) - 4 * s, 8 * s, 8 * s);
        if (best.S.HasValue) using (var b = new SolidBrush(SessionC)) g.FillEllipse(b, x - 4 * s, Y(best.S.Value) - 4 * s, 8 * s, 8 * s);
        var lt = best.T.ToLocalTime();
        string text = Days[(int)lt.DayOfWeek] + " " + lt.ToString("HH:mm") + "\nсесія " + Fmt(best.S) + " · тиждень " + Fmt(best.W);
        var size = g.MeasureString(text, small);
        float bx = x + 10 * s + size.Width + 16 * s > plot.Right ? x - 10 * s - size.Width - 16 * s : x + 10 * s;
        var box = new RectangleF(bx, plot.Top + 6 * s, size.Width + 16 * s, size.Height + 10 * s);
        using (var path = Rounded(Rectangle.Round(box), (int)(6 * s)))
        using (var b = new SolidBrush(C(48, 48, 48)))
        using (var pen = new Pen(C(80, 80, 80))) { g.FillPath(b, path); g.DrawPath(pen, path); }
        using (var b = new SolidBrush(TextC)) g.DrawString(text, small, b, box.X + 8 * s, box.Y + 5 * s);
    }
    static string Fmt(double? v) { return v.HasValue ? (int)Math.Round(v.Value, MidpointRounding.AwayFromZero) + "%" : "—"; }

    static GraphicsPath Rounded(Rectangle r, int radius) {
        int d = Math.Max(1, radius * 2);
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    // ClaudeLimits.exe --preview-graph out.png: графік на вигаданих даних (для перевірки вигляду).
    public static void Preview(string path, bool week) {
        var rnd = new Random(7);
        var d = new List<Sample>();
        double w = 5, sess = 0;
        for (var t = DateTime.UtcNow.AddDays(-7); t < DateTime.UtcNow; t = t.AddMinutes(5)) {
            int h = t.ToLocalTime().Hour;
            if (h % 5 == 0 && t.Minute < 5) sess = 0;                                  // скидання сесії
            if (h >= 9 && h < 20) { double add = rnd.NextDouble() * 1.6; sess = Math.Min(100, sess + add); w = Math.Min(100, w + add / 9); }
            if (h >= 1 && h < 8 && rnd.Next(4) == 0) continue;                        // комп спав
            d.Add(new Sample { T = t, S = sess, W = w });
        }
        using (var f = new GraphForm(d) { week = week })
        using (var bmp = new Bitmap(f.ClientSize.Width, f.ClientSize.Height))
        using (var g = Graphics.FromImage(bmp)) {
            f.hoverX = f.ClientSize.Width * 2 / 3;
            f.Draw(g, bmp.Width, bmp.Height);   // перший прохід рахує розміри графіка для підказки
            f.Draw(g, bmp.Width, bmp.Height);
            bmp.Save(path, ImageFormat.Png);
        }
    }
}

// Гучність звуку на динаміках зараз (0..1) через Windows Core Audio: IMMDeviceEnumerator → динаміки за замовчуванням →
// IAudioMeterInformation.GetPeakValue. Нічого не записує, лише читає «стрілку гучності». Якщо динаміки змінилися
// (навушники тощо) або сталася помилка — раз на 10 с пробує підключитися знову.
class AudioMeter {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }
    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float peak); }

    IAudioMeterInformation meter;
    DateTime nextTry = DateTime.MinValue;
    public float Level() {
        try {
            if (meter == null) {
                if (DateTime.UtcNow < nextTry) return 0;
                nextTry = DateTime.UtcNow.AddSeconds(10);
                var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
                IMMDevice dev;
                if (en.GetDefaultAudioEndpoint(0 /* eRender */, 1 /* eMultimedia */, out dev) != 0 || dev == null) return 0;
                var iid = typeof(IAudioMeterInformation).GUID;
                object o;
                if (dev.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out o) != 0) return 0;
                meter = (IAudioMeterInformation)o;
            }
            float peak;
            if (meter.GetPeakValue(out peak) != 0) { meter = null; return 0; }
            return peak;
        } catch { meter = null; return 0; }
    }
}

class App : ApplicationContext {
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

    public static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ClaudeLimits");
    static readonly string StateFile = Path.Combine(Dir, "state.json");
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    readonly NotifyIcon tray = new NotifyIcon();
    readonly ContextMenuStrip menu = new ContextMenuStrip();
    readonly Crab crab = new Crab();
    readonly TaskbarWidget widget = new TaskbarWidget();
    bool barMode = true;   // користувач хоче великого краба на панелі задач
    bool cyberMode = true; // кіберпанк-режим: глітч від 95% і кіберпсихоз
    bool onBar;            // і він зараз справді там (інакше — іконка в треї)
    GraphForm graph;
    Usage usage;
    string error;
    DateTime? updated;
    DateTime nextAllowed = DateTime.MinValue;
    int failures;
    bool stale;
    double? top;
    int frame;
    int iconSize = 16;
    Icon icon; IntPtr iconHandle;

    // Дебаг: примусово показати певний стан краба (0 = реальні дані)
    int debugIndex;
    static readonly object[][] DebugStates = {
        new object[] { "Авто (реальні дані)", null, null },
        new object[] { "Бадьорий · 20%", 20.0, null },
        new object[] { "Спокійний · 60%", 60.0, null },
        new object[] { "Стурбований · 80%", 80.0, null },
        new object[] { "Виснажений · 92%", 92.0, null },
        new object[] { "Паніка · 97%", 97.0, null },
        new object[] { "Спить", 20.0, "sleep" },
        new object[] { "Свято", 20.0, "party" },
        new object[] { "Новорічна шапка", 20.0, "winter" },
        new object[] { "Махає", 20.0, "wave" },
        new object[] { "П'є каву", 20.0, "coffee" },
        new object[] { "Окуляри", 20.0, "shades" },
        new object[] { "Хелловін", 20.0, "halloween" },
        new object[] { "Сумує (тебе нема)", 20.0, "lonely" },
        new object[] { "Обідає", 20.0, "lunch" },
        new object[] { "Диско (п'ятниця)", 20.0, "disco" },
        new object[] { "Сонний понеділок", 20.0, "monday" },
        new object[] { "Падає", 20.0, "fall" },
        new object[] { "Летить на батуті", 20.0, "fly" },
        new object[] { "Клацає біля курсора", 20.0, "snip" },
        new object[] { "Валентинка", 20.0, "valentine" },
        new object[] { "День Незалежності", 20.0, "flag" },
        new object[] { "Танцює (кібер-дискотека)", 20.0, "dance" } };
    // Для глітчу й кіберпсихозу — справжня цифра, яку бачить користувач (настрій краба рахує сесію з поправкою −3).
    double Hot { get {
        if (debugIndex != 0) return ShownPct ?? 0;
        double h = 0;
        if (usage != null && Live(usage.Session) != null) h = usage.Session.Percent;
        if (usage != null && Live(usage.Weekly) != null) h = Math.Max(h, usage.Weekly.Percent);
        return h;
    } }
    double? ShownPct { get { return debugIndex == 0 ? top : (double?)(double)DebugStates[debugIndex][1]; } }

    // Випадкові витівки: окуляри на 10 с раз на 15–30 хв, прогулянка раз на 25–45 хв.
    const int PerMinute = 400;   // кадрів по 0.15 с
    readonly Random rng = new Random();
    int nextCool = 15 * PerMinute, nextWalk = 25 * PerMinute, nextGull = 45 * PerMinute, nextPsycho = PerMinute;   // чайка — раз на 40–90 хв

    public App(bool selftest = false) {
        tray.ContextMenuStrip = menu;
        // Ліва кнопка теж відкриває меню, як на Mac (у Windows за замовчуванням лише права).
        tray.MouseUp += (s, e) => { if (e.Button == MouseButtons.Left) ShowMenu(); };
        widget.Clicked += ShowMenu;
        menu.Opening += (s, e) => { crab.WaveUntil = frame + 18; BuildMenu(); e.Cancel = false; };   // клік по крабу: махає

        Load();
        Place();
        Render();
        if (updated.HasValue && (DateTime.UtcNow - updated.Value).TotalSeconds < 300) {
            // Дані з диска ще свіжі (молодші за 5 хв): не питаємо сервер і не пишемо «сервер просить зачекати».
            if (nextAllowed < updated.Value.AddSeconds(300)) { nextAllowed = updated.Value.AddSeconds(300); stale = false; }
        }
        else if (DateTime.UtcNow >= nextAllowed) Refresh();
        Render();
        var anim = new System.Windows.Forms.Timer { Interval = 150 };
        anim.Tick += (s, e) => Tick();
        anim.Start();
        // Поки краб у русі (сцена, кидок, чайка) — ще й ~30 перемальовувань на секунду між кадрами, щоб рух був плавним.
        // Удома цей таймер вимкнений.
        smooth.Tick += (s, e) => { if (onBar && widget.Busy) DrawWidget(); else smooth.Stop(); };
        var poll = new System.Windows.Forms.Timer { Interval = 300 * 1000 };
        poll.Tick += (s, e) => Refresh();
        poll.Start();
        if (selftest) SelfTest();
    }

    // ClaudeLimits.exe --selftest: програма сама клікає й тягає краба справжніми подіями миші (як людина) і пише, що сталося,
    // у консоль (якщо запущено з термінала) і в %APPDATA%\ClaudeLimits\selftest.log. Рухає справжню мишку ~15 с, потім повертає її.
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
    async void SelfTest() {
        var log = new List<string>();
        bool ok = true;
        Action<string> say = m => { log.Add(m); Console.WriteLine("[selftest] " + m); };
        Action<bool, string> check = (pass, what) => { say((pass ? "✓ " : "✗ ") + what); ok &= pass; };
        var old = Cursor.Position;
        try {
            await Task.Delay(2500);
            if (!onBar) { check(false, "краб не на панелі задач (тест — лише для великого краба)"); }
            else {
                // 1) Клік по цифрах відкриває меню.
                Cursor.Position = widget.TextPoint; await Task.Delay(150);
                mouse_event(0x2, 0, 0, 0, IntPtr.Zero); await Task.Delay(60); mouse_event(0x4, 0, 0, 0, IntPtr.Zero);
                await Task.Delay(800);
                check(menu.Visible, "клік по цифрах відкриває меню");
                menu.Close(); await Task.Delay(500);
                // 2) Схопив краба й потягнув угору — краб у руці.
                var c = widget.CrabPoint;
                Cursor.Position = c; await Task.Delay(150);
                mouse_event(0x2, 0, 0, 0, IntPtr.Zero);
                for (int i = 1; i <= 12; i++) { Cursor.Position = new Point(c.X + 6 * i, c.Y - 20 * i); await Task.Delay(40); }
                await Task.Delay(200);
                check(widget.ModeName == "Drag", "схопив і потягнув: краб у руці (" + widget.ModeName + ")");
                // 3) Різкий мах управо й відпустив — кидок.
                var p = Cursor.Position;
                for (int i = 1; i <= 4; i++) { Cursor.Position = new Point(p.X + 30 * i, p.Y - 5 * i); await Task.Delay(15); }
                mouse_event(0x4, 0, 0, 0, IntPtr.Zero);
                await Task.Delay(60);
                check(widget.ModeName == "Fall" && widget.ThrowVX > 0, "кинув управо: летить (" + widget.ModeName + ", швидкість " + widget.ThrowVX.ToString("0") + " px/кадр)");
                Cursor.Position = old;
                // 4) Падає, відскакує, паморочиться, повертається додому.
                var seen = new List<string>();
                for (int i = 0; i < 30 && widget.ModeName != "Home"; i++) {
                    await Task.Delay(600);
                    if (seen.Count == 0 || seen[seen.Count - 1] != widget.ModeName) seen.Add(widget.ModeName);
                }
                say("   шлях: Fall → " + string.Join(" → ", seen));
                check(widget.ModeName == "Home", "після кидка повернувся додому");
            }
        } catch (Exception ex) { check(false, "виняток: " + ex.Message); }
        Cursor.Position = old;
        say(ok ? "УСЕ ДОБРЕ" : "Є ПРОБЛЕМИ");
        try { Directory.CreateDirectory(Dir); File.WriteAllLines(Path.Combine(Dir, "selftest.log"), log); } catch { }
        tray.Visible = false; widget.Close();
        Environment.Exit(ok ? 0 : 1);
    }

    // Дробовий час у кадрах анімації (0.15 с): номер кадру плюс скільки минуло від нього.
    readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
    readonly System.Windows.Forms.Timer smooth = new System.Windows.Forms.Timer { Interval = 33 };
    long tickAt;
    double FT { get { return frame + Math.Min(1.0, (clock.ElapsedMilliseconds - tickAt) / 150.0); } }

    // MARK: збереження (останні цифри й пауза переживають перезапуск)
    void Save() {
        var d = new Dictionary<string, object>();
        d["na"] = nextAllowed.ToString("o");
        d["bar"] = barMode;
        d["cyber"] = cyberMode;
        if (usage != null) {
            if (usage.Session != null) { d["sp"] = usage.Session.Percent; d["sr"] = Iso(usage.Session.Resets); }
            if (usage.Weekly != null) { d["wp"] = usage.Weekly.Percent; d["wr"] = Iso(usage.Weekly.Resets); }
            d["at"] = Iso(updated);
        }
        try { Directory.CreateDirectory(Dir); File.WriteAllText(StateFile, new JavaScriptSerializer().Serialize(d)); } catch { }
    }
    // Якщо краба колись запускали інструменти застосунку Claude (він встановлений як MSIX-пакет), його записи в %APPDATA%
    // потрапили в «пісочницю» пакета: %LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\ClaudeLimits. Переносимо їх
    // у справжню папку: state.json — якщо там новіші дані, history.csv — об'єднуємо без повторів. Перенесене перейменовуємо
    // на *.migrated, щоб не переносити двічі.
    static void MigrateFromSandbox() {
        try {
            var pk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Packages");
            if (!Directory.Exists(pk)) return;
            foreach (var pkg in Directory.GetDirectories(pk, "Claude_*")) {
                var src = Path.Combine(pkg, "LocalCache", "Roaming", "ClaudeLimits");
                if (!Directory.Exists(src) || string.Equals(Path.GetFullPath(src), Path.GetFullPath(Dir), StringComparison.OrdinalIgnoreCase)) continue;
                Directory.CreateDirectory(Dir);
                var sState = Path.Combine(src, "state.json");
                if (File.Exists(sState)) {
                    if (!File.Exists(StateFile) || File.GetLastWriteTimeUtc(sState) > File.GetLastWriteTimeUtc(StateFile)) File.Copy(sState, StateFile, true);
                    File.Move(sState, sState + ".migrated");
                }
                var sHist = Path.Combine(src, "history.csv");
                if (File.Exists(sHist)) {
                    var dHist = Path.Combine(Dir, "history.csv");
                    var all = new SortedSet<string>(StringComparer.Ordinal);
                    if (File.Exists(dHist)) foreach (var l in File.ReadAllLines(dHist)) if (l.Length > 0) all.Add(l);
                    foreach (var l in File.ReadAllLines(sHist)) if (l.Length > 0) all.Add(l);
                    File.WriteAllLines(dHist, all);
                    File.Move(sHist, sHist + ".migrated");
                }
            }
        } catch (Exception ex) { ErrorLog.Write(ex); }
    }

    void Load() {
        MigrateFromSandbox();
        try {
            var d = (Dictionary<string, object>)new JavaScriptSerializer().DeserializeObject(File.ReadAllText(StateFile));
            DateTime? na = Date(d, "na"); if (na.HasValue) nextAllowed = na.Value;
            object bar; if (d.TryGetValue("bar", out bar) && bar is bool) barMode = (bool)bar;
            object cyb; if (d.TryGetValue("cyber", out cyb) && cyb is bool) cyberMode = (bool)cyb;
            DateTime? at = Date(d, "at"); if (!at.HasValue) return;
            usage = new Usage { Session = Lim(d, "sp", "sr"), Weekly = Lim(d, "wp", "wr") };
            updated = at; stale = true;
        } catch { }
    }
    static string Iso(DateTime? t) { return t.HasValue ? t.Value.ToString("o") : null; }
    static DateTime? Date(Dictionary<string, object> d, string k) {
        object v;
        if (!d.TryGetValue(k, out v) || !(v is string)) return null;
        return DateTime.Parse((string)v, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind).ToUniversalTime();
    }
    static Limit Lim(Dictionary<string, object> d, string p, string r) {
        object v;
        if (!d.TryGetValue(p, out v) || v == null) return null;
        return new Limit { Percent = Convert.ToDouble(v, CultureInfo.InvariantCulture), Resets = Date(d, r) };
    }

    // MARK: дані
    // Той самий OAuth-токен, яким користується Claude Code. Читаємо при кожному запиті й нікуди не пишемо.
    static string Token() {
        try {
            string dir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrEmpty(dir)) dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            var j = (Dictionary<string, object>)new JavaScriptSerializer().DeserializeObject(File.ReadAllText(Path.Combine(dir, ".credentials.json")));
            return ((Dictionary<string, object>)j["claudeAiOauth"])["accessToken"] as string;
        } catch { return null; }
    }

    // async void не має кому ловити помилки (програма закрилась би), тому вся робота в RefreshCore під try/catch.
    async void Refresh() {
        try { await RefreshCore(); }
        catch { error = "Несподівана помилка оновлення"; try { Render(); } catch { } }
    }

    // Вхід Claude Code живе ~8 год, і оновлює його сам Claude Code, коли ним користуються. Якщо вхід прострочився,
    // краб тихо «будить» Claude Code коротким запитом на найлегшій моделі (крихта ліміту, ~5 с), і той сам оновлює
    // свій файл входу. Не частіше ніж раз на 30 хв — щоб не витрачати ліміт, якщо, наприклад, ти вийшов з облікового запису.
    DateTime nextWake = DateTime.MinValue;
    bool waking;
    static DateTime? LoginExpiry() {
        try {
            string dir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrEmpty(dir)) dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            var j = (Dictionary<string, object>)new JavaScriptSerializer().DeserializeObject(File.ReadAllText(Path.Combine(dir, ".credentials.json")));
            object e;
            if (!((Dictionary<string, object>)j["claudeAiOauth"]).TryGetValue("expiresAt", out e) || e == null) return null;
            return DateTimeOffset.FromUnixTimeMilliseconds(Convert.ToInt64(e, CultureInfo.InvariantCulture)).UtcDateTime;
        } catch { return null; }
    }
    static bool LoginFresh() { var e = LoginExpiry(); return !e.HasValue || e.Value > DateTime.UtcNow.AddMinutes(2); }

    async Task<bool> WakeClaude() {
        if (DateTime.UtcNow < nextWake) return false;
        nextWake = DateTime.UtcNow.AddMinutes(30);
        waking = true; Render();
        int code = await Task.Run(() => RunClaudeWake());
        waking = false;
        if (code != 0) ErrorLog.Write(new Exception("Не вдалося розбудити Claude Code (код " + code + ")"));
        return LoginFresh();
    }

    // Запускає `claude -p ok` без вікна в папці краба. Повертає код виходу (-1 — не знайшли claude або не дочекались).
    public static int RunClaudeWake() {
        try {
            string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin", "claude.exe");
            if (!File.Exists(exe)) exe = "claude";                              // інакше шукаємо в PATH
            Directory.CreateDirectory(Dir);
            var psi = new System.Diagnostics.ProcessStartInfo(exe, "-p ok --model haiku --no-session-persistence --strict-mcp-config") {
                UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Dir,
                RedirectStandardOutput = true, RedirectStandardError = true };
            using (var p = System.Diagnostics.Process.Start(psi)) {
                p.StandardOutput.ReadToEndAsync(); p.StandardError.ReadToEndAsync();   // читаємо вивід, щоб процес не застряг
                if (!p.WaitForExit(120 * 1000)) { try { p.Kill(); } catch { } return -1; }
                return p.ExitCode;
            }
        } catch { return -1; }
    }

    async Task RefreshCore() {
        if (DateTime.UtcNow < nextAllowed) { Render(); return; }
        nextAllowed = DateTime.UtcNow.AddSeconds(30);   // не частіше ніж раз на 30 с
        if (!LoginFresh()) await WakeClaude();          // вхід Claude Code прострочився — нехай він його оновить
        string tok = Token();
        if (tok == null) { error = "Не знайшов вхід у Claude Code"; Render(); return; }

        int code = 0; string body = null, retryAfter = null, netError = null;
        try {
            await Task.Run(() => {
                var req = (HttpWebRequest)WebRequest.Create("https://api.anthropic.com/api/oauth/usage");
                req.Timeout = 15000;
                req.UserAgent = "ClaudeLimits-Windows";
                req.Headers["Authorization"] = "Bearer " + tok;
                req.Headers["anthropic-beta"] = "oauth-2025-04-20";
                HttpWebResponse resp;
                try { resp = (HttpWebResponse)req.GetResponse(); }
                catch (WebException we) { resp = we.Response as HttpWebResponse; if (resp == null) throw; }
                using (resp) {
                    code = (int)resp.StatusCode;
                    retryAfter = resp.Headers["Retry-After"];
                    using (var r = new StreamReader(resp.GetResponseStream())) body = r.ReadToEnd();
                }
            });
        } catch (Exception ex) { netError = ex.InnerException != null ? ex.InnerException.Message : ex.Message; }

        if (netError != null) { error = "Немає мережі (" + netError + ")"; Render(); return; }
        if (code == 429) {
            double ra;
            double.TryParse(retryAfter ?? "", NumberStyles.Float, CultureInfo.InvariantCulture, out ra);
            double backoff = Math.Min(300 * Math.Pow(2, failures), 1800);
            failures++;
            nextAllowed = DateTime.UtcNow.AddSeconds(Math.Max(ra, backoff));
            stale = true;
            error = null;
            Save();
            Render(); return;
        }
        Dictionary<string, object> j = null;
        if (code == 200) try { j = new JavaScriptSerializer().DeserializeObject(body) as Dictionary<string, object>; } catch { }
        if (j == null) {
            // 401 — вхід недійсний. Пробуємо розбудити Claude Code; якщо він оновив вхід — одразу повторюємо запит.
            if (code == 401 && await WakeClaude()) { nextAllowed = DateTime.UtcNow; await RefreshCore(); return; }
            error = code == 401 ? "Вхід Claude Code застарів: запусти claude у терміналі" : "Помилка " + code;
            Render(); return;
        }
        double? before = usage != null && usage.Session != null ? (double?)usage.Session.Percent : null;
        usage = new Usage { Session = Parse(j, "five_hour"), Weekly = Parse(j, "seven_day") };
        if (before.HasValue && usage.Session != null && before.Value - usage.Session.Percent >= 15) crab.CelebrateUntil = frame + 100;
        error = null; stale = false; failures = 0; updated = DateTime.UtcNow; Save(); Render();
        History.Add(updated.Value, usage);
        if (graph != null && !graph.IsDisposed) graph.SetData(History.Load(DateTime.UtcNow.AddDays(-8)));
    }

    static Limit Parse(Dictionary<string, object> j, string k) {
        object o, u, s;
        if (!j.TryGetValue(k, out o)) return null;
        var d = o as Dictionary<string, object>;
        if (d == null || !d.TryGetValue("utilization", out u) || u == null) return null;
        var l = new Limit { Percent = Convert.ToDouble(u, CultureInfo.InvariantCulture) };
        DateTimeOffset t;
        if (d.TryGetValue("resets_at", out s) && s is string &&
            DateTimeOffset.TryParse((string)s, CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) l.Resets = t.UtcDateTime;
        return l;
    }

    // MARK: інтерфейс
    static string Left(DateTime? d) {
        if (!d.HasValue) return "—";
        int s = (int)(d.Value - DateTime.UtcNow).TotalSeconds;
        if (s <= 0) return "зараз";
        int days = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60;
        if (days > 0) return days + "д " + h + "г";
        if (h > 0) return h + "г " + m + "хв";
        return m + "хв";
    }
    // Ліміт, час скидання якого вже минув, — застарілий: показуємо «—» і не враховуємо в настрої краба.
    static Limit Live(Limit l) { return l != null && l.Resets.HasValue && l.Resets.Value <= DateTime.UtcNow ? null : l; }
    static string HM(DateTime utc) { return utc.ToLocalTime().ToString("HH:mm"); }
    static string Pct(Limit l) { return l == null ? "—" : (int)Math.Round(l.Percent, MidpointRounding.AwayFromZero) + "%"; }

    void Tick() {
        frame++;
        tickAt = clock.ElapsedMilliseconds;
        if (onBar && widget.Busy && !smooth.Enabled) smooth.Start();
        if (frame % 7 == 0) { Place(); CheckIdle(); }   // приблизно раз на секунду
        ListenMusic();
        if (frame >= nextCool) { crab.CoolUntil = frame + 67; nextCool = frame + rng.Next(15 * PerMinute, 30 * PerMinute); }
        if (frame >= nextWalk) { if (CanPlay()) BeginScene(); nextWalk = frame + rng.Next(25 * PerMinute, 45 * PerMinute); }
        if (frame >= nextGull) { if (CanPlay()) BeginGull(); nextGull = frame + rng.Next(40 * PerMinute, 90 * PerMinute); }
        // Кіберпсихоз: лише від 95% у кіберпанк-режимі, раз на 2–5 хв.
        if (frame >= nextPsycho) {
            if (cyberMode && onBar && Hot >= 95 && !widget.Busy && !menu.Visible) BeginPsycho();
            nextPsycho = frame + rng.Next(2 * PerMinute, 5 * PerMinute);
        }
        // Поки тебе немає, малюємо вчетверо рідше: краб однаково дрімає, а процесор відпочиває.
        if (crab.Lonely && !widget.Busy && frame % 4 != 0) return;
        if (onBar) DrawWidget(); else SetIcon();
    }

    // Музика: Windows сам каже, наскільки гучно зараз грає звук на динаміках (Core Audio, без дозволів і без запису звуку).
    // Танець починається, коли звук триває ~1 с (сповіщення не рахуються), і стихає через ~2 с тиші.
    // Удар — коли гучність стрибнула помітно вище середньої.
    readonly AudioMeter audio = new AudioMeter();
    int loudFrames, quietFrames, lastBeat;
    float avgLevel;
    void ListenMusic() {
        float lvl = audio.Level();
        if (lvl > 0.03f) { loudFrames++; quietFrames = 0; } else { quietFrames++; if (quietFrames > 14) loudFrames = 0; }
        avgLevel = avgLevel * 0.9f + lvl * 0.1f;
        bool on = loudFrames >= 7;
        crab.Music = on ? Math.Max(0.05f, lvl) : 0;
        if (on && lvl > avgLevel * 1.2f && lvl > 0.06f && frame - lastBeat >= 2) { crab.Beat++; lastBeat = frame; }
    }

    // Скільки секунд ніхто не чіпав мишку й клавіатуру. 10+ хв — краб сумує; повернувся — радіє.
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public int cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    void CheckIdle() {
        var li = new LASTINPUTINFO { cbSize = Marshal.SizeOf(typeof(LASTINPUTINFO)) };
        if (!GetLastInputInfo(ref li)) return;
        uint idle = ((uint)Environment.TickCount - li.dwTime) / 1000;
        bool was = crab.Lonely;
        crab.Lonely = idle >= 600;
        if (was && !crab.Lonely) crab.WelcomeUntil = frame + 30;
    }

    // Витівки — лише у доброму настрої: не вночі, не від 90%, коли ти поруч, меню закрите й краб удома.
    bool CanPlay() {
        int hour = DateTime.Now.Hour;
        return onBar && ShownPct.HasValue && ShownPct < 90 && hour >= 7 && hour < 23 && !menu.Visible && !crab.Lonely && !widget.Busy;
    }
    // Раз на 25–45 хв — одна сцена, як на Mac (`pickScene`): 50% прогулянка, 20% хованка за «Пуск», 30% батут.
    // Якщо вибрана сцена неможлива (немає відкритих програм чи місця) — просто прогулянка.
    // scene: -1 — випадково, 0 — прогулянка, 1 — хованка, 2 — батут (з дебаг-меню).
    async void BeginScene(int scene = -1) {
        if (!onBar || widget.Busy) return;
        try {
            var lay = await Task.Run(() => TaskbarWidget.FindLayout());
            // Ваги як на Mac (`pickScene`): з 20 — 8 прогулянка, 3 хованка, 4 батут, 5 ловить курсор.
            int r = scene >= 0 ? new[] { 0, 8, 11, 15 }[scene] : rng.Next(20);
            bool ok = false;
            if (r >= 15) ok = widget.StartSnip(FT);
            else if (r >= 11) ok = widget.StartTramp(FT, lay, rng);
            else if (r >= 8) ok = widget.StartHide(FT, lay);
            // Маршрут прогулянки — від половини до всього шляху до кнопки «Пуск», щоразу інший.
            if (!ok) widget.StartWalk(FT, lay.StartLeft, 0.5 + rng.NextDouble() * 0.5);
            if (onBar && widget.Busy) smooth.Start();
        } catch { }
    }
    async void BeginPsycho() {
        if (!onBar || widget.Busy) return;
        try {
            var lay = await Task.Run(() => TaskbarWidget.FindLayout());
            if (widget.StartPsycho(FT, lay, rng)) smooth.Start();
        } catch { }
    }
    async void BeginGull() {
        if (!onBar) return;
        try {
            var lay = await Task.Run(() => TaskbarWidget.FindLayout());
            widget.StartGull(FT, lay.StartLeft);
            if (onBar && widget.Busy) smooth.Start();
        } catch { }
    }

    // Великий краб на панелі задач, коли можна; інакше маленька іконка в треї.
    void Place() {
        onBar = widget.Place(barMode);
        if (tray.Visible == onBar) tray.Visible = !onBar;
    }

    // Ліва кнопка теж відкриває меню, як на Mac (у Windows за замовчуванням лише права).
    // Для трею — приватний метод NotifyIcon: він сам ставить меню над панеллю задач і закриває його кліком деінде.
    void ShowMenu() {
        if (onBar) { widget.ShowMenu(menu); return; }
        var show = typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic);
        if (show != null) show.Invoke(tray, null);
    }

    void DrawWidget() {
        var lines = new List<TaskbarWidget.Seg[]>();
        if (usage != null) {
            lines.Add(new[] { new TaskbarWidget.Seg("5г ", 0), Num(Live(usage.Session), -3) });
            lines.Add(new[] { new TaskbarWidget.Seg("Т ", 0), Num(Live(usage.Weekly), 0) });
        } else lines.Add(new[] { new TaskbarWidget.Seg(error == null ? "…" : "⚠", 1) });
        widget.Cyber = cyberMode;
        crab.Cyber = cyberMode;
        widget.Hot = Hot;
        widget.Draw(crab, ShownPct, FT, lines, crab.LightTaskbar, tray.Text);
    }
    // Колір цифри: від 70% помаранчева й жирна, від 90% червона (для сесії з поправкою -3).
    static TaskbarWidget.Seg Num(Limit l, double shift) {
        if (l == null) return new TaskbarWidget.Seg("—", 1);
        double v = l.Percent + shift;
        return new TaskbarWidget.Seg(Pct(l), v >= 90 ? 3 : v >= 70 ? 2 : 1);
    }

    void SetIcon() {
        double? s, w;
        if (debugIndex == 0) {
            s = usage != null && usage.Session != null ? (double?)usage.Session.Percent : null;
            w = usage != null && usage.Weekly != null ? (double?)usage.Weekly.Percent : null;
        } else { s = ShownPct + 3; w = ShownPct; }   // у дебазі обидві смужки показують вибраний рівень
        crab.Cyber = cyberMode;
        // У треї мишки, прогулянок і чайок немає.
        crab.Hover = crab.Walking = crab.Held = crab.Dizzy = crab.Scared = crab.Angry = false; crab.LookDx = 0;
        using (var bmp = crab.Draw(ShownPct, frame, iconSize, s, w)) {
            IntPtr h = bmp.GetHicon();
            var next = Icon.FromHandle(h);
            tray.Icon = next;
            // Старі іконки звільняємо, інакше за день анімації Windows вичерпає ресурси.
            if (icon != null) { icon.Dispose(); DestroyIcon(iconHandle); }
            icon = next; iconHandle = h;
        }
    }

    void Render() {
        // Краб реагує на "зважений" рівень: сесія скидається за години, тому її беремо з поправкою -3,
        // а тиждень - як є (вичерпаний тиждень болить найдовше).
        top = null;
        if (usage != null && Live(usage.Session) != null) top = usage.Session.Percent - 3;
        if (usage != null && Live(usage.Weekly) != null && (!top.HasValue || usage.Weekly.Percent > top)) top = usage.Weekly.Percent;
        iconSize = SystemInformation.SmallIconSize.Width;
        crab.LightTaskbar = LightTaskbar();
        SetIcon();

        // Текст поруч з іконкою в треї неможливий, тому цифри — у підказці при наведенні.
        string tip;
        if (usage != null) {
            tip = "Claude · 5г " + Pct(Live(usage.Session)) + " · Т " + Pct(Live(usage.Weekly));
            if (updated.HasValue) tip += "\n" + (stale ? "дані з " : "оновлено ") + HM(updated.Value);
        } else tip = error == null ? "Claude Limits · …" : "⚠ " + error;
        tray.Text = tip.Length > 63 ? tip.Substring(0, 63) : tip;

        if (onBar) DrawWidget();
        if (!menu.Visible) BuildMenu();
    }

    void BuildMenu() {
        menu.Items.Clear();
        Action<string> row = s => menu.Items.Add(new ToolStripMenuItem(s) { Enabled = false });
        if (usage != null) {
            if (usage.Session != null) row(Live(usage.Session) == null ? "Сесія 5 год: ліміт скинувся · чекаю свіжих даних"
                                             : "Сесія 5 год: " + Pct(usage.Session) + " · оновиться через " + Left(usage.Session.Resets));
            if (usage.Weekly != null) row(Live(usage.Weekly) == null ? "Тиждень: ліміт скинувся · чекаю свіжих даних"
                                            : "Тиждень: " + Pct(usage.Weekly) + " · оновиться через " + Left(usage.Weekly.Resets));
        }
        if (waking) row("Оновлюю вхід Claude Code…");
        if (error != null) row("⚠ " + error);
        if (usage == null && error == null) {
            if (nextAllowed > DateTime.UtcNow) row("Сервер тимчасово обмежив запити · наступна спроба о " + HM(nextAllowed));
            else row("Завантажую…");
        }
        if (updated.HasValue) row(stale ? "Дані з " + HM(updated.Value) + " · сервер просить зачекати" : "Оновлено " + HM(updated.Value));
        menu.Items.Add(new ToolStripSeparator());

        var chart = new ToolStripMenuItem("Графік використання…");
        chart.Click += (s, e) => {
            if (graph == null || graph.IsDisposed) { graph = new GraphForm(History.Load(DateTime.UtcNow.AddDays(-8))); graph.Show(); }
            else { graph.WindowState = FormWindowState.Normal; graph.Activate(); }
        };
        menu.Items.Add(chart);

        var dbg = new ToolStripMenuItem("Дебаг: стани краба");
        for (int i = 0; i < DebugStates.Length; i++) {
            int idx = i;
            var it = new ToolStripMenuItem((string)DebugStates[i][0]) { Checked = i == debugIndex };
            it.Click += (s, e) => { debugIndex = idx; crab.Force = (string)DebugStates[idx][2]; Render(); };
            dbg.DropDownItems.Add(it);
        }
        dbg.DropDownItems.Add(new ToolStripSeparator());
        var walk = new ToolStripMenuItem("Піти погуляти зараз") { Enabled = onBar };
        walk.Click += (s, e) => BeginScene(0);
        var trampNow = new ToolStripMenuItem("Батут зараз") { Enabled = onBar };
        trampNow.Click += (s, e) => BeginScene(2);
        var hideNow = new ToolStripMenuItem("Сховатися за «Пуск»") { Enabled = onBar };
        hideNow.Click += (s, e) => BeginScene(1);
        // Курсор у момент кліку — над пунктом меню, тож краб стрибне туди, де було меню.
        var snipNow = new ToolStripMenuItem("Зловити курсор зараз") { Enabled = onBar };
        snipNow.Click += (s, e) => BeginScene(3);
        var gullNow = new ToolStripMenuItem("Прилетіла чайка") { Enabled = onBar };
        gullNow.Click += (s, e) => BeginGull();
        var hello = new ToolStripMenuItem("Ти повернувся (привіт!)");
        hello.Click += (s, e) => { crab.WelcomeUntil = frame + 30; };
        dbg.DropDownItems.Add(trampNow);
        dbg.DropDownItems.Add(hideNow);
        dbg.DropDownItems.Add(snipNow);
        var psychoNow = new ToolStripMenuItem("Кіберпсихоз зараз") { Enabled = onBar && cyberMode };
        psychoNow.Click += (s, e) => BeginPsycho();
        dbg.DropDownItems.Add(psychoNow);
        dbg.DropDownItems.Add(gullNow);
        dbg.DropDownItems.Add(hello);
        // Навмисна помилка в анімації: програма має жити далі, а в errors.log з'явиться запис.
        var oops = new ToolStripMenuItem("Тестова помилка (перевірити страховку)");
        oops.Click += (s, e) => {
            var t = new System.Windows.Forms.Timer { Interval = 100 };
            t.Tick += (o, a) => { t.Dispose(); throw new InvalidOperationException("Тестова помилка з дебаг-меню"); };
            t.Start();
        };
        dbg.DropDownItems.Add(oops);
        dbg.DropDownItems.Add(walk);
        menu.Items.Add(dbg);

        var cyber = new ToolStripMenuItem("Кіберпанк-режим") { Checked = cyberMode };
        cyber.Click += (s, e) => { cyberMode = !cyberMode; Save(); Render(); };
        menu.Items.Add(cyber);
        var big = new ToolStripMenuItem("Великий краб зліва на панелі задач") { Checked = barMode };
        big.Click += (s, e) => { barMode = !barMode; Save(); Place(); Render(); };
        menu.Items.Add(big);
        var auto = new ToolStripMenuItem("Запускати при вході в Windows") { Checked = Autostart };
        auto.Click += (s, e) => { Autostart = !Autostart; };
        menu.Items.Add(auto);
        var refresh = new ToolStripMenuItem("Оновити зараз");
        refresh.Click += (s, e) => Refresh();
        menu.Items.Add(refresh);
        var quit = new ToolStripMenuItem("Вийти");
        quit.Click += (s, e) => { tray.Visible = false; widget.Close(); ExitThread(); };
        menu.Items.Add(quit);
    }

    // Автозапуск: запис у реєстрі поточного користувача (прав адміністратора не треба).
    static bool Autostart {
        get {
            using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                return k != null && string.Equals(k.GetValue("ClaudeLimits") as string, Quoted(), StringComparison.OrdinalIgnoreCase);
        }
        set {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey)) {
                if (value) k.SetValue("ClaudeLimits", Quoted()); else k.DeleteValue("ClaudeLimits", false);
            }
        }
    }
    static string Quoted() { return "\"" + Application.ExecutablePath + "\""; }

    static bool LightTaskbar() {
        using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")) {
            object v = k == null ? null : k.GetValue("SystemUsesLightTheme");
            return v is int && (int)v == 1;
        }
    }

    // ClaudeLimits.exe --preview out.png: усі стани краба однією картинкою (для перевірки без запуску).
    public static void Preview(string path) {
        var states = new object[][] {
            new object[] { 20.0, null }, new object[] { 60.0, null }, new object[] { 80.0, null }, new object[] { 92.0, null },
            new object[] { 97.0, null }, new object[] { 20.0, "sleep" }, new object[] { 20.0, "party" },
            new object[] { 20.0, "winter" }, new object[] { 20.0, "wave" }, new object[] { 20.0, "coffee" },
            new object[] { 60.0, "shades" }, new object[] { 20.0, "halloween" }, new object[] { 20.0, "hover" },
            new object[] { 20.0, "lonely" }, new object[] { 20.0, "welcome" }, new object[] { 20.0, "lunch" },
            new object[] { 20.0, "disco" }, new object[] { 20.0, "monday" }, new object[] { 20.0, "held" },
            new object[] { 20.0, "dizzy" }, new object[] { 20.0, "scared" }, new object[] { 20.0, "angry" },
            new object[] { 20.0, "fall" }, new object[] { 20.0, "fly" }, new object[] { 20.0, "snip" },
            new object[] { 20.0, "valentine" }, new object[] { 20.0, "flag" } };
        int[] sizes = { 20, 32 }; int[] frames = { 0, 3, 6 };
        const int cell = 160, pad = 10;
        using (var sheet = new Bitmap(states.Length * (cell + pad) + pad, sizes.Length * frames.Length * (cell + pad) + pad))
        using (var g = Graphics.FromImage(sheet)) {
            g.Clear(Color.FromArgb(32, 32, 32));
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            int r = 0;
            foreach (int size in sizes)
                foreach (int f in frames) {
                    for (int c = 0; c < states.Length; c++) {
                        var force = (string)states[c][1];
                        var crab = new Crab { Force = force, Hover = force == "hover", Held = force == "held", Dizzy = force == "dizzy",
                                              Scared = force == "scared", Angry = force == "angry" };
                        double p = (double)states[c][0];
                        using (var img = crab.Draw(p, f, size, p + 3, p))
                            g.DrawImage(img, pad + c * (cell + pad), pad + r * (cell + pad), cell, cell);
                    }
                    r++;
                }
            sheet.Save(path, ImageFormat.Png);
        }
    }
}

// Загальна страховка: будь-яка непередбачена помилка пишеться в %APPDATA%\ClaudeLimits\errors.log, а програма
// живе далі — без вікна «Microsoft .NET Framework» (а з анімації воно вискакувало б знову й знову).
// Однакова помилка пишеться не частіше ніж раз на хвилину; файл більший за 200 КБ починається заново.
static class ErrorLog {
    static string lastText;
    static DateTime lastAt;
    public static void Write(Exception ex) {
        try {
            if (ex == null) return;
            string text = ex.ToString();
            if (text == lastText && (DateTime.Now - lastAt).TotalSeconds < 60) return;
            lastText = text; lastAt = DateTime.Now;
            Directory.CreateDirectory(App.Dir);
            string path = Path.Combine(App.Dir, "errors.log");
            if (File.Exists(path) && new FileInfo(path).Length > 200 * 1024) File.Delete(path);
            File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + text + "\r\n\r\n");
        } catch { }
    }
}

static class Program {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);

    [STAThread]
    static void Main(string[] args) {
        // Страховку вмикаємо найпершою, ще до створення будь-яких вікон (інакше Windows не дозволить).
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (s, e) => ErrorLog.Write(e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (s, e) => ErrorLog.Write(e.ExceptionObject as Exception);
        SetProcessDPIAware();   // інакше на екрані з масштабом 125%+ Windows розмиває іконку
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        int i = Array.IndexOf(args, "--preview");
        if (i >= 0 && i + 1 < args.Length) { App.Preview(args[i + 1]); return; }
        if (Array.IndexOf(args, "--wake-test") >= 0) {     // перевірка: чи вміє краб запустити Claude Code
            var sw = System.Diagnostics.Stopwatch.StartNew();
            int rc = App.RunClaudeWake();
            File.WriteAllText(Path.Combine(App.Dir, "wake-test.log"), "exit=" + rc + " seconds=" + sw.Elapsed.TotalSeconds.ToString("0.0"));
            return;
        }
        i = Array.IndexOf(args, "--preview-graph");
        if (i >= 0 && i + 1 < args.Length) {
            GraphForm.Preview(args[i + 1], false);
            GraphForm.Preview(Path.ChangeExtension(args[i + 1], null) + "-week.png", true);
            return;
        }

        bool selftest = Array.IndexOf(args, "--selftest") >= 0;
        if (selftest) { AttachConsole(-1); Console.OutputEncoding = System.Text.Encoding.UTF8; Console.WriteLine(); }   // пишемо в термінал, з якого запустили

        bool first;
        using (new Mutex(true, @"Local\ClaudeLimits", out first)) {
            if (!first) {   // вже запущено
                if (selftest) Console.WriteLine("[selftest] Спершу закрий Claude Limits (меню краба → «Вийти»).");
                return;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new App(selftest));
        }
    }
}
