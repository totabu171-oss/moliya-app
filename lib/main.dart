import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- Ma'lumotlar ----------

const incomeCats = {
  'Inson': ['Maosh', 'Boshqa'],
  'Tadbirkor': ['Tushum', 'Boshqa'],
  'Buxgalter': ['Xizmat haqi', 'Boshqa'],
};
const expenseCats = {
  'Inson': ['Uy-joy', 'Oziq-ovqat', 'Transport', 'Xaridlar', 'Boshqa'],
  'Tadbirkor': ['Tovar', 'Ish haqi', 'Ijara', 'Reklama', 'Soliq', 'Boshqa'],
  'Buxgalter': ['Ijara', 'Soliq', 'Dastur', 'Boshqa'],
};

String fmt(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

class Tx {
  final bool income;
  final String category;
  final double amount;
  final DateTime date;
  Tx(this.income, this.category, this.amount, this.date);
  Map<String, dynamic> toJson() =>
      {'i': income, 'c': category, 'a': amount, 'd': date.toIso8601String()};
  factory Tx.fromJson(Map<String, dynamic> j) => Tx(j['i'] as bool,
      j['c'] as String, (j['a'] as num).toDouble(), DateTime.parse(j['d'] as String));
}

class Reminder {
  final String title;
  final double amount;
  final DateTime due;
  Reminder(this.title, this.amount, this.due);
  Map<String, dynamic> toJson() =>
      {'t': title, 'a': amount, 'd': due.toIso8601String()};
  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
      j['t'] as String, (j['a'] as num).toDouble(), DateTime.parse(j['d'] as String));
  int get days {
    final n = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .difference(DateTime(n.year, n.month, n.day))
        .inDays;
  }
}

class Insight {
  final Color color;
  final IconData icon;
  final String text;
  Insight(this.color, this.icon, this.text);
}

Color statusColor(int d) =>
    d < 0 ? Colors.red : (d <= 7 ? Colors.orange : Colors.green);
String dayText(int d) =>
    d < 0 ? "${-d} kun o'tib ketgan" : (d == 0 ? 'Bugun' : '$d kun qoldi');

// ---------- Holat va mantiq: hisoblaydi, eslatadi, tahlil qiladi, tejatadi, yo'naltiradi ----------

class Store extends ChangeNotifier {
  List<Tx> txs = [];
  List<Reminder> reminders = [];
  String mode = 'Inson';

  DateTime get cur => DateTime.now();
  DateTime get prev => DateTime(DateTime.now().year, DateTime.now().month - 1);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = p.getString('mode') ?? 'Inson';
    txs = (jsonDecode(p.getString('txs') ?? '[]') as List)
        .map((e) => Tx.fromJson(e as Map<String, dynamic>))
        .toList();
    reminders = (jsonDecode(p.getString('rem') ?? '[]') as List)
        .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('mode', mode);
    await p.setString('txs', jsonEncode(txs.map((e) => e.toJson()).toList()));
    await p.setString('rem', jsonEncode(reminders.map((e) => e.toJson()).toList()));
  }

  void setMode(String m) { mode = m; save(); }
  void addTx(Tx t) { txs.add(t); save(); }
  void removeTx(Tx t) { txs.remove(t); save(); }
  void addReminder(Reminder r) { reminders.add(r); save(); }
  void removeReminder(Reminder r) { reminders.remove(r); save(); }

  // 1. Hisoblaydi
  double total(DateTime m, bool income) => txs
      .where((t) => t.income == income && t.date.year == m.year && t.date.month == m.month)
      .fold(0.0, (a, t) => a + t.amount);

  Map<String, double> byCat(DateTime m) {
    final r = <String, double>{};
    for (final t in txs) {
      if (!t.income && t.date.year == m.year && t.date.month == m.month) {
        r[t.category] = (r[t.category] ?? 0) + t.amount;
      }
    }
    return r;
  }

  // 2 + 3. Eslatadi va tahlil qiladi
  List<Insight> insights() {
    final out = <Insight>[];
    final inc = total(cur, true), exp = total(cur, false);
    if (inc > 0) {
      final r = exp / inc * 100;
      out.add(r > 75
          ? Insight(Colors.red, Icons.warning_amber, "Bu oy daromadingizning ${r.round()}% sarflandi.")
          : Insight(Colors.green, Icons.check_circle, "Daromadingizning ${r.round()}% sarflandi. Nazorat yaxshi."));
    }
    final c = byCat(cur), p = byCat(prev);
    c.forEach((k, v) {
      final o = p[k] ?? 0;
      if (o > 0 && v > o * 1.15) {
        out.add(Insight(Colors.orange, Icons.trending_up,
            "$k xarajati o'tgan oyga nisbatan ${((v - o) / o * 100).round()}% oshgan."));
      }
    });
    final pn = total(prev, true) - total(prev, false);
    final cn = inc - exp;
    if (pn > 0 && inc > 0 && cn != pn) {
      final d = ((cn - pn) / pn * 100).round();
      out.add(d >= 0
          ? Insight(Colors.green, Icons.trending_up, "Sof pul oqimi o'tgan oyga nisbatan $d% yaxshilangan.")
          : Insight(Colors.red, Icons.trending_down, "Sof pul oqimi o'tgan oyga nisbatan ${-d}% yomonlashgan."));
    }
    final soon = reminders.where((r) => r.days >= 0 && r.days <= 7).length;
    final late = reminders.where((r) => r.days < 0).length;
    if (late > 0) out.add(Insight(Colors.red, Icons.notification_important, "$late ta to'lov muddati o'tib ketgan."));
    if (soon > 0) out.add(Insight(Colors.orange, Icons.notifications_active, "Keyingi 7 kunda $soon ta to'lov/muddat bor."));
    return out;
  }

  // 4. Tejatadi
  String? savingTip() {
    final c = byCat(cur), p = byCat(prev);
    String? best;
    double gain = 0;
    c.forEach((k, v) {
      final o = p[k] ?? 0;
      if (o > 0 && v - o > gain) { gain = v - o; best = k; }
    });
    if (best == null) return null;
    return "$best xarajatini o'tgan oy darajasiga qaytarsangiz, oyiga ${fmt(gain)} so'm tejaladi.";
  }

  // 5. Yo'naltiradi
  List<String> investTips() {
    final left = total(cur, true) - total(cur, false);
    if (left <= 0) return [];
    final grow = mode == 'Tadbirkor'
        ? "Biznesni kengaytirish yoki tovarga"
        : "Maqsadli jamg'arma yoki o'zingizga investitsiyaga";
    return [
      "Favqulodda zaxira (50%): ${fmt(left * .5)} so'm",
      "Depozit yoki obligatsiya (30%): ${fmt(left * .3)} so'm",
      "$grow (20%): ${fmt(left * .2)} so'm",
    ];
  }

  void seed() {
    final n = DateTime.now();
    final c = DateTime(n.year, n.month, 1), p = DateTime(n.year, n.month - 1, 15);
    void add(bool i, String k, double a, DateTime d) => txs.add(Tx(i, k, a, d));
    add(true, 'Maosh', 5000000, c);
    add(false, 'Uy-joy', 1500000, c);
    add(false, 'Oziq-ovqat', 900000, c);
    add(false, 'Transport', 400000, c);
    add(false, 'Xaridlar', 450000, c);
    add(false, 'Boshqa', 600000, c);
    add(true, 'Maosh', 5000000, p);
    add(false, 'Uy-joy', 1500000, p);
    add(false, 'Oziq-ovqat', 880000, p);
    add(false, 'Transport', 340000, p);
    add(false, 'Xaridlar', 400000, p);
    add(false, 'Boshqa', 500000, p);
    reminders.add(Reminder('Ijara to\'lovi', 8000000, n.add(const Duration(days: 5))));
    reminders.add(Reminder('Soliq muddati', 0, n.add(const Duration(days: 3))));
    save();
  }
}

final store = Store();

// ---------- Ilova ----------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(const MoneyApp());
}

class MoneyApp extends StatelessWidget {
  const MoneyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Moliyaviy yordamchi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2F9E6E), useMaterial3: true),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (ctx, _) {
        final pages = <Widget>[HomePage(), TxPage(), RemPage(), AnalysisPage()];
        return Scaffold(
          appBar: AppBar(title: const Text('Moliyaviy yordamchi')),
          body: pages[i],
          floatingActionButton: i == 1
              ? FloatingActionButton(onPressed: () => addTxSheet(ctx), child: const Icon(Icons.add))
              : i == 2
                  ? FloatingActionButton(onPressed: () => addReminderSheet(ctx), child: const Icon(Icons.add_alert))
                  : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: i,
            onDestinationSelected: (v) => setState(() => i = v),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard), label: 'Bosh'),
              NavigationDestination(icon: Icon(Icons.swap_vert), label: 'Kirim-chiqim'),
              NavigationDestination(icon: Icon(Icons.notifications), label: 'Eslatma'),
              NavigationDestination(icon: Icon(Icons.insights), label: 'Tahlil'),
            ],
          ),
        );
      },
    );
  }
}

Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );

// ---------- Bosh sahifa ----------

class HomePage extends StatelessWidget {
  HomePage({super.key});

  Widget _row(String l, double v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l),
          Text("${fmt(v)} so'm",
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ]),
      );

  Widget _chip(String l, int n, Color c) => Expanded(
        child: Card(
          color: c.withOpacity(.15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text('$n', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Text(l),
            ]),
          ),
        ),
      );

  List<Widget> _person() {
    final inc = store.total(store.cur, true), exp = store.total(store.cur, false);
    final cats = store.byCat(store.cur);
    final big = cats.values.fold<double>(1, (a, b) => b > a ? b : a);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Daromad', inc),
            _row('Xarajat', exp),
            const Divider(),
            _row('Qolgan', inc - exp, bold: true),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: inc > 0 ? (exp / inc).clamp(0.0, 1.0) : 0),
          ]),
        ),
      ),
      sectionTitle('Pul qayerga ketmoqda?'),
      for (final e in cats.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 100, child: Text(e.key)),
            Expanded(child: LinearProgressIndicator(value: e.value / big, minHeight: 12)),
            SizedBox(width: 90, child: Text(fmt(e.value), textAlign: TextAlign.right)),
          ]),
        ),
    ];
  }

  List<Widget> _accountant() {
    final rs = [...store.reminders]..sort((a, b) => a.days.compareTo(b.days));
    final red = rs.where((r) => r.days < 0).length;
    final yellow = rs.where((r) => r.days >= 0 && r.days <= 7).length;
    return [
      Row(children: [
        _chip('Vaqtida', rs.length - red - yellow, Colors.green),
        _chip('Yaqin', yellow, Colors.orange),
        _chip('Muammo', red, Colors.red),
      ]),
      sectionTitle('Mijozlar muddatlari'),
      if (rs.isEmpty) const Text("Eslatma bo'limida mijoz muddatlarini qo'shing."),
      for (final r in rs)
        ListTile(
          leading: Icon(Icons.circle, color: statusColor(r.days)),
          title: Text(r.title),
          subtitle: Text(dayText(r.days)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Inson', label: Text('Inson')),
          ButtonSegment(value: 'Tadbirkor', label: Text('Tadbirkor')),
          ButtonSegment(value: 'Buxgalter', label: Text('Buxgalter')),
        ],
        selected: {store.mode},
        onSelectionChanged: (v) => store.setMode(v.first),
      ),
      const SizedBox(height: 16),
      ...(store.mode == 'Buxgalter' ? _accountant() : _person()),
      if (store.txs.isEmpty && store.reminders.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: OutlinedButton(
              onPressed: store.seed, child: const Text("Namuna ma'lumot yuklash")),
        ),
    ]);
  }
}

// ---------- Kirim-chiqim ----------

class TxPage extends StatelessWidget {
  TxPage({super.key});
  @override
  Widget build(BuildContext context) {
    final list = [...store.txs]..sort((a, b) => b.date.compareTo(a.date));
    if (list.isEmpty) {
      return const Center(child: Text("Hali yozuv yo'q. + tugmasini bosing."));
    }
    return ListView(children: [
      for (final t in list)
        Dismissible(
          key: ObjectKey(t),
          background: Container(color: Colors.red),
          onDismissed: (_) => store.removeTx(t),
          child: ListTile(
            leading: Icon(t.income ? Icons.south_west : Icons.north_east,
                color: t.income ? Colors.green : Colors.red),
            title: Text(t.category),
            subtitle: Text('${t.date.day}.${t.date.month}.${t.date.year}'),
            trailing: Text("${t.income ? '+' : '-'}${fmt(t.amount)}"),
          ),
        ),
    ]);
  }
}

void addTxSheet(BuildContext context) {
  bool income = false;
  String? cat;
  final ctrl = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      final cats = (income ? incomeCats : expenseCats)[store.mode]!;
      cat = cats.contains(cat) ? cat : cats.first;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Xarajat')),
              ButtonSegment(value: true, label: Text('Daromad')),
            ],
            selected: {income},
            onSelectionChanged: (v) => setSt(() => income = v.first),
          ),
          DropdownButton<String>(
            value: cat,
            isExpanded: true,
            items: [for (final c in cats) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setSt(() => cat = v),
          ),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Summa (so'm)"),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final a = double.tryParse(ctrl.text.replaceAll(' ', ''));
              if (a == null || a <= 0) return;
              store.addTx(Tx(income, cat!, a, DateTime.now()));
              Navigator.pop(ctx);
            },
            child: const Text('Saqlash'),
          ),
        ]),
      );
    }),
  );
}

// ---------- Eslatmalar ----------

class RemPage extends StatelessWidget {
  RemPage({super.key});
  @override
  Widget build(BuildContext context) {
    final rs = [...store.reminders]..sort((a, b) => a.days.compareTo(b.days));
    if (rs.isEmpty) {
      return const Center(child: Text("Eslatma yo'q. Tugma orqali qo'shing."));
    }
    return ListView(children: [
      for (final r in rs)
        Dismissible(
          key: ObjectKey(r),
          background: Container(color: Colors.red),
          onDismissed: (_) => store.removeReminder(r),
          child: ListTile(
            leading: Icon(Icons.circle, color: statusColor(r.days)),
            title: Text(r.title),
            subtitle: Text(dayText(r.days)),
            trailing: r.amount > 0 ? Text("${fmt(r.amount)} so'm") : null,
          ),
        ),
    ]);
  }
}

void addReminderSheet(BuildContext context) {
  final title = TextEditingController(), amt = TextEditingController();
  DateTime due = DateTime.now().add(const Duration(days: 7));
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Nom (masalan: Ijara, Soliq, Mijoz hisoboti)'),
          ),
          TextField(
            controller: amt,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Summa (ixtiyoriy)"),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: due,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (d != null) setSt(() => due = d);
            },
            child: Text('Muddat: ${due.day}.${due.month}.${due.year}'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              store.addReminder(Reminder(title.text.trim(),
                  double.tryParse(amt.text.replaceAll(' ', '')) ?? 0, due));
              Navigator.pop(ctx);
            },
            child: const Text('Saqlash'),
          ),
        ]),
      );
    }),
  );
}

// ---------- Tahlil, tejash, investitsiya ----------

class AnalysisPage extends StatelessWidget {
  AnalysisPage({super.key});
  @override
  Widget build(BuildContext context) {
    final ins = store.insights();
    final tips = store.investTips();
    return ListView(padding: const EdgeInsets.all(16), children: [
      sectionTitle('Tahlil'),
      if (ins.isEmpty) const Text("Tahlil uchun ma'lumot yetarli emas."),
      for (final i in ins)
        Card(child: ListTile(leading: Icon(i.icon, color: i.color), title: Text(i.text))),
      sectionTitle('Tejash'),
      Card(
        child: ListTile(
          leading: const Icon(Icons.savings),
          title: Text(store.savingTip() ?? "Taklif uchun kamida ikki oylik ma'lumot kerak."),
        ),
      ),
      sectionTitle("Investitsiyaga yo'naltirish"),
      if (tips.isEmpty) const Text("Oy oxirida qolgan pul bo'lsa, taqsimot taklif qilinadi."),
      for (final t in tips)
        Card(child: ListTile(leading: const Icon(Icons.trending_up), title: Text(t))),
      const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Text(
          "Taqsimot taxminiy namuna va moliyaviy maslahat emas. Qaror qilishdan oldin mutaxassis bilan maslahatlashing.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    ]);
  }
}

