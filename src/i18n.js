// Language: English text is the key; Arabic lives in AR. t('Wreck {n} cars', { n: 5 }) fills placeholders.
// Static markup uses data-t (text) or data-t-aria (aria-label); applyLang() rewrites them and flips the page to RTL.
import { save } from './save.js';

const AR = {
  // lobby
  'Your ride': 'سيارتك', 'Selected': 'مختارة', 'Owned': 'بملكك', 'Locked': 'مقفلة', 'Upgrading': 'تطوير',
  'Driver: {d}': 'السائق: {d}', 'Special: {s}': 'القدرة: {s}',
  'Speed': 'السرعة', 'Armor': 'الدروع', 'Guns': 'الرشاش', 'Rockets': 'الصواريخ',
  'Upgrade': 'تطوير', 'Garage': 'الكراج', 'Play': 'العب', 'Enter the arena': 'ادخل الحلبة',
  'Driver file': 'ملف السائق', 'Back': 'رجوع', 'Select': 'اختيار', 'Buy': 'شراء', 'Need {n}': 'بدك {n}',
  'Workshop': 'الورشة', 'Max': 'أقصى', 'Scrap': 'خردة', 'Scrap points': 'نقاط الخردة',
  'Daily contracts': 'المهام اليومية', 'Battle history': 'سجل المعارك', 'Music': 'الموسيقى', 'Settings': 'الإعدادات', 'Sound effects': 'المؤثرات',
  'Previous car': 'السيارة السابقة', 'Next car': 'السيارة التالية', 'Pause': 'إيقاف مؤقت',
  // upgrades
  'Machine Gun': 'الرشاش', 'Bullet damage': 'ضرر الرصاص', 'Rocket damage and blast': 'ضرر وانفجار الصواريخ',
  'Maximum health': 'أقصى صحة', 'Engine': 'المحرك', 'Top speed and acceleration': 'السرعة القصوى والتسارع',
  'Special': 'القدرة الخاصة', 'Stronger, faster recharge': 'أقوى، وشحن أسرع',
  // setup
  'Iron Cup qualifier': 'تصفيات كأس الحديد', 'Choose your battle': 'اختار معركتك', 'Difficulty': 'الصعوبة', 'Your best': 'أفضل نتيجة',
  'Fight': 'قاتل', 'Deathmatch': 'معركة حتى الموت', 'Survival': 'البقاء',
  'Three lives each. Most kills wears the crown. 5 minutes.': 'لكل سيارة ٣ أرواح. التاج لصاحب أكتر قتلات. ٥ دقايق.',
  'Endless waves that all hunt you. How far can you go?': 'موجات ما بتخلص وكلها عم تلاحقك. لوين فيك توصل؟',
  '{n} enemies': '{n} أعداء', 'Wave {n}': 'الموجة {n}',
  'Win: {a} + {b}/kill': 'الفوز: {a} + {b} لكل قتلة', '{a}/kill + wave bonuses': '{a} لكل قتلة + مكافآت الموجات',
  'Rookie': 'مبتدئ', 'Veteran': 'محترف', 'Warlord': 'أمير حرب',
  // maps
  'Scrapyard': 'ساحة الخردة', 'Refinery': 'المصفاة', 'Dust Bowl': 'وادي الغبار', 'Shanty Town': 'مدينة الصفيح', 'The Outpost': 'المخفر',
  'Junk piles and a watchtower': 'أكوام خردة وبرج مراقبة', 'Fuel tanks ready to blow': 'خزانات وقود جاهزة تنفجر',
  'Open ground, rock pillars': 'أرض مفتوحة وأعمدة صخر', 'Three towers, tight streets': 'تلات أبراج وشوارع ضيقة', 'Fight around the fortress': 'قتال حوالين الحصن',
  'Dumpsters, cages and tarp-covered drums around an old watchtower. Plenty of cover, short sight lines.': 'حاويات زبالة وأقفاص وبراميل مغطاية حوالين برج مراقبة قديم. في كتير مخابئ والرؤية قصيرة.',
  'Concrete pads, storage tanks, gas carts and rows of fuel barrels. One stray rocket and the whole row goes up.': 'أرضيات إسمنت وخزانات وعربات غاز وصفوف براميل وقود. صاروخ طايش واحد وبيطير الصف كلو.',
  'A dried lake bed broken by rock pillars, barrier lines and a lonely outpost. Fast cars rule here.': 'قاع بحيرة ناشفة فيها أعمدة صخر وحواجز ومخفر وحيد. هون السيارات السريعة هيي الملكة.',
  'Three scrap towers form a ring around the market square. Every corner is an ambush.': 'تلات أبراج خردة حوالين ساحة السوق. كل زاوية فيها كمين.',
  'A fortified tower inside a ring of concrete barriers with two gates. Circle it, breach it, hold it.': 'برج محصّن جوا حلقة حواجز إسمنت إلها بوابتين. دور حوله، اقتحمه، وامسكه.',
  // history
  'Service record': 'سجل الخدمة', 'Close': 'إغلاق', 'Matches': 'المعارك', 'Wins': 'الانتصارات', 'Win rate': 'نسبة الفوز', 'Kills': 'القتلات',
  'Result': 'النتيجة', 'Arena': 'الحلبة', 'Car': 'السيارة', 'Points': 'النقاط', 'Victory': 'انتصار', 'Left': 'انسحاب', 'Wrecked': 'تحطمت',
  'No battles yet. Your record starts with the first match.': 'لسا ما في معارك. سجلك بيبلش من أول معركة.',
  // contracts
  'Resets at midnight': 'بتتجدد نص الليل', 'Complete': 'مكتملة', 'Contract complete': 'مهمة مكتملة',
  'New contracts in {n} hours': 'مهام جديدة بعد {n} ساعات', 'New contracts in {n} hour': 'مهام جديدة بعد ساعة',
  'Wreck {n} cars': 'حطّم {n} سيارات', 'Wreck {n} cars with rockets': 'حطّم {n} سيارات بالصواريخ', 'Blow up {n} fuel barrels': 'فجّر {n} براميل وقود',
  'Grab {n} airdrops': 'التقط {n} إنزالات جوية', 'Score a Double Wreck': 'حقق تحطيم مزدوج', 'Claim {n} bounties': 'خود التاج {n} مرات',
  'Win a match on {map}': 'اربح معركة بـ{map}', 'Win on Veteran or Warlord': 'اربح على محترف أو أمير حرب', 'Reach wave {n} in Survival': 'وصال للموجة {n} بالبقاء',
  // settings
  'Steering': 'التوجيه', 'Direction': 'اتجاهي', 'Classic': 'كلاسيكي', 'Auto gas': 'بنزين تلقائي',
  'Point the stick where you want to go': 'وجّه العصا للمكان يلي بدك تروح عليه', 'Up to drive, left and right to steer': 'لفوق لتمشي، يمين ويسار لتلف', 'The car drives itself; you only steer': 'السيارة بتمشي لحالها وإنت بس بتلف',
  'Button layout': 'ترتيب الأزرار', 'Move and resize the touch buttons': 'حرّك أزرار اللمس وغيّر حجمها', 'Edit': 'تعديل',
  'Volume': 'الصوت', 'Master': 'العام', 'Effects': 'المؤثرات', 'Graphics': 'الرسوميات', 'Auto': 'تلقائي', 'High': 'عالي', 'Medium': 'متوسط', 'Low': 'منخفض',
  'Auto: now {q}, adjusts to keep the game smooth': 'تلقائي: هلأ {q}، وبيتعدل ليضل اللعب ناعم', 'Fixed quality': 'جودة ثابتة',
  'Touch controls': 'أزرار اللمس', 'Bigger buttons suit large tablets': 'الأزرار الكبيرة أحسن للتابلت', 'Small': 'صغير', 'Normal': 'عادي', 'Large': 'كبير',
  'Language': 'اللغة', 'Credits': 'الشكر',
  'Game by': 'لعبة من تطوير', 'Environment art': 'تصميم البيئة', 'Fonts': 'الخطوط',
  // editor
  'Edit controls': 'تعديل التحكم', 'Drag a button to move it. Tap one, then use the slider to resize it.': 'اسحب الزر لتحركه. اضغط على زر وبعدين استعمل الشريط لتغير حجمه.',
  'Size': 'الحجم', 'Reset': 'افتراضي', 'Save': 'حفظ', 'STICK': 'العصا',
  // HUD
  'FIRE': 'نار', 'RKT': 'صاروخ', 'SPEC': 'قدرة', 'KILL': 'قتلة', 'KILLS': 'قتلات', 'enemy left': 'عدو باقي', 'enemies left': 'أعداء باقيين',
  'wave · hostiles': 'موجة · أعداء', 'You': 'إنت', 'you': 'إنت', '{k} wrecked {v}': '{k} حطّم {v}', '{v} crashed out': '{v} تحطم لحالو',
  'W A S D drive · Space fire · F rocket · E special · Esc pause': 'W A S D سواقة · Space نار · F صاروخ · E قدرة · Esc إيقاف',
  'F fires the {p} ({n})': 'F بيطلق {p} ({n})', 'Lives': 'الأرواح',
  'BACK IN THE FIGHT': 'رجعت عالمعركة', 'Last life': 'آخر روح', '{n} lives left': 'باقيلك {n} أرواح',
  'YOU TAKE THE CROWN': 'التاج إلك', 'NEW LEADER': 'متصدر جديد', 'Every car is hunting you now': 'كل السيارات عم تلاحقك هلأ', '{car} has the most kills': '{car} معو أكتر قتلات',
  'CROWN CLAIMED': 'خطفت التاج', 'WRECKED': 'تحطمت', 'Last life · back in 3s': 'آخر روح · راجع بعد ٣ ثواني', '{n} lives left · back in 3s': 'باقي {n} أرواح · راجع بعد ٣ ثواني',
  'WAVE': 'الموجة', 'VICTORY': 'انتصار', 'TIME UP': 'خلص الوقت', 'FIGHT': 'قاتل',
  'WAVE {n}': 'الموجة {n}', '{n} hostiles inbound': '{n} أعداء جايين', 'WAVE {n} CLEARED': 'نضفت الموجة {n}', '+{n} · armor patched': '+{n} · الدروع تصلحت',
  '{p} EMPTY': 'خلص {p}', '{p} · rocket button': '{p} · زر الصاروخ', '{car} grabbed the {p}': '{car} أخد {p}',
  'AIRDROP INCOMING': 'إنزال جوي جاي', 'Follow the blue smoke': 'لحّق الدخان الأزرق', 'ARTILLERY STRIKE': 'قصف مدفعي', 'Get out of the red circles': 'اطلع من الدواير الحمرا',
  'TANK RUPTURE': 'خزان عم ينفجر', 'A fuel tank is about to blow': 'في خزان وقود رح ينفجر', 'SANDSTORM': 'عاصفة رملية', 'Visibility dropping': 'الرؤية عم تقل',
  '+ ARMOR REPAIRED': '+ تصلحت الدروع', '+4 ROCKETS': '+٤ صواريخ', '+{n} streak bonus': '+{n} مكافأة سلسلة',
  'DOUBLE WRECK': 'تحطيم مزدوج', 'TRIPLE WRECK': 'تحطيم تلاتي', 'RAMPAGE': 'هيجان', 'UNSTOPPABLE': 'ما حدا بيوقفك',
  'Railgun': 'المدفع الكهربائي', 'Napalm': 'النابالم', 'Mini Nuke': 'القنبلة النووية الصغيرة',
  'Instant beam, punches through armor': 'شعاع فوري بيخرق الدروع', 'Rockets leave burning ground': 'الصواريخ بتترك الأرض عم تحترق', 'One rocket. Huge blast.': 'صاروخ واحد. انفجار ضخم.',
  'RAIL': 'شعاع', 'NAPLM': 'نابالم', 'NUKE': 'نووي',
  // pause / results
  'Match paused': 'المعركة متوقفة', 'Pit stop': 'استراحة', 'Resume': 'كمّل', 'Leave the arena': 'اطلع من الحلبة', 'Fight again': 'قاتل مرة تانية',
  'Time in arena': 'الوقت بالحلبة', 'New personal best': 'رقم قياسي جديد', 'Victory bonus': 'مكافأة الفوز', 'Show-up pay': 'أجرة الحضور', 'Scrap earned': 'الخردة يلي جمعتها',
  'First blood': 'أول دم', 'Crown claimed': 'خطفت التاج', 'Wave {n} cleared': 'الموجة {n} انتهت', 'Double wreck': 'تحطيم مزدوج', 'Triple wreck': 'تحطيم تلاتي', 'Rampage': 'هيجان', 'Unstoppable': 'ما حدا بيوقفك',
  // loader / rotate
  'Turn your phone': 'دوّر موبايلك', 'IronMetal is played in landscape.': 'آيرون ميتال بتنلعب والشاشة بالعرض.',
  // cars: drivers, specials, stories
  'Sami "Spanner" Haddad': 'سامي "المفتاح" حداد', 'Layla Qasim': 'ليلى قاسم', 'Old Man Fares': 'العم فارس', 'Nadia "Torch" Saleh': 'نادية "الشعلة" صالح',
  'Brother Yusuf': 'الأخ يوسف', 'Karim Zein': 'كريم زين', 'The Brothers Antar': 'الإخوة عنتر', 'Hussain "The Engineer"': 'حسين "المهندس"',
  'Nitro Burst': 'دفعة نيترو', 'Ram Charge': 'هجمة نطح', 'Shockwave': 'موجة صدمة', 'Flamethrower': 'قاذف لهب', 'Iron Shield': 'الدرع الحديدي',
  'Seeker Missiles': 'صواريخ ملاحِقة', 'Mine Layer': 'زارع ألغام', 'Rocket Barrage': 'وابل صواريخ',
  'Doubles top speed for 3 seconds.': 'بيضاعف السرعة القصوى ٣ ثواني.', 'Lunges forward. Anything you hit takes heavy damage.': 'بتندفع لقدام، وكل شي بتضربو بياكل ضرر كبير.',
  'Slams the ground, throwing nearby cars back and hurting them.': 'بتضرب الأرض وبترمي السيارات القريبة لورا وبتأذيها.', 'Sprays fire ahead for 3 seconds, burning everything in the cone.': 'بترش نار لقدام ٣ ثواني وبتحرق كل شي قدامك.',
  'Blocks all damage for 4 seconds.': 'بيصد كل الضرر ٤ ثواني.', 'Fires three missiles that hunt the nearest enemies.': 'بتطلق تلات صواريخ بتلاحق أقرب الأعداء.',
  'Drops three proximity mines behind you.': 'بترمي تلات ألغام ورا ضهرك.', 'Unleashes eight rockets in a wide fan.': 'بتطلق تمان صواريخ بشكل مروحة عريضة.',
  "A mechanic who rebuilt his father's sedan from three wrecks and a prayer. It rattles, it leaks, and it has never once failed to start.": 'ميكانيكي رجّع عمّر سيارة أبوه من تلات خردات ودعوة. بتطقطق وبتنقط زيت، بس ولا مرة رفضت تشتغل.',
  'Raised by smugglers on the salt flats, Layla drives like the ground is on fire. Her buggy weighs nothing and forgives nothing.': 'تربّت بين المهربين بسهول الملح، وليلى بتسوق كأنو الأرض عم تحترق. سيارتها خفيفة متل الريشة وما بتسامح حدا.',
  'Fares towed wrecks off the highway for forty years. Now he builds them. The crane on his back has lifted heavier things than your car.': 'فارس ضل أربعين سنة يسحب السيارات المحطمة عن الأوتوستراد. هلأ صار يصنعها. الونش يلي على ضهرو رفع أتقل من سيارتك.',
  'She lost her garage to a raider fire and kept the flamethrower that started it. Nobody in the arena wants to be close to her bumper.': 'خسرت كراجها بحريق عملوه الغزاة، وخلّت قاذف اللهب يلي بلّش الحريق. ما حدا بالحلبة بدو يقرب من صدامها.',
  'A former convoy guard who armored an aid van until it stopped looking like one. He prays before every match and reloads during the prayer.': 'حارس قوافل قديم درّع فان مساعدات لحتى صار ما بيشبهو. بيصلي قبل كل معركة وبيعبي ذخيرة وهو عم يصلي.',
  'An ex-racer banned from every track that still exists. The Viper is fast, low, and carries missiles that find you on their own.': 'متسابق سابق ممنوع من كل حلبة سباق لسا موجودة. الفايبر سريعة وواطية ومعها صواريخ بتلاقيك لحالها.',
  'Two brothers, one rig, no brakes. They haul a trailer full of mines and they are not shy about unloading it.': 'أخين، شاحنة وحدة، وبلا فرامل. بيجرّوا مقطورة مليانة ألغام وما بيستحوا يفضوها.',
  'Built in secret from refinery steel and stolen military parts, the Warhorse is the machine every clan whispers about. Its driver designed the arena it fights in.': 'انبنت بالسر من حديد المصفاة وقطع عسكرية مسروقة، والوورهورس هيي الآلة يلي كل العشاير عم تتهامس عنها. سائقها هو يلي صمم الحلبة يلي عم تقاتل فيها.',
};

let lang = 'en';
export function getLang() { return lang; }
export function t(s, vars) {
  let out = (lang === 'ar' && AR[s]) || s;
  if (vars) for (const k in vars) out = out.split(`{${k}}`).join(vars[k]);
  return out;
}
// Arabic digits read better inside Arabic text; numbers in HUD counters stay Latin for legibility.
export function applyLang(next) {
  lang = next === 'ar' ? 'ar' : 'en';
  const root = document.documentElement;
  root.lang = lang; root.dir = lang === 'ar' ? 'rtl' : 'ltr';
  root.classList.toggle('ar', lang === 'ar');
  for (const el of document.querySelectorAll('[data-t]')) { if (el.dataset.en == null) el.dataset.en = el.textContent.trim(); el.textContent = t(el.dataset.en); }
  for (const el of document.querySelectorAll('[data-t-aria]')) { if (el.dataset.enAria == null) el.dataset.enAria = el.getAttribute('aria-label'); el.setAttribute('aria-label', t(el.dataset.enAria)); }
}
export function initLang() { applyLang((save.get().lang) || 'en'); }
