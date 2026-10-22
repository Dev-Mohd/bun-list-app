# بن لست · BunnList

تطبيق آيفون (SwiftUI، iOS 17) لاكتشاف محاصيل القهوة المنزلية وجمعها. المواصفات: [`docs/spec/BunnList-Master-Spec-v2.3.md`](docs/spec/BunnList-Master-Spec-v2.3.md).

**الحالة: C00 وC01، نسخة محلية.** لا حسابات ولا خادم ولا نشر. الدليل والمسح تجريبيان وموسومان؛ لا تقييمات أو أعداد مستخدمين مزعومة. التقدم والبوابات في [`docs/TASKS.md`](docs/TASKS.md).

## البنية

```
project.yml                  مصدر مشروع Xcode (XcodeGen 2.42.0)؛ BunnList.xcodeproj مولد وغير محفوظ في git
Packages/BunnListCore/       قواعد المنتج — لا SwiftUI/UIKit/SwiftData، تُختبر على Linux
  Sources/BunnListCore/Resources/fixtures.json   الدليل التجريبي (6 دفعات، 4 منتجات)
BunnList/                    التطبيق: SwiftUI + SwiftData
BunnListTests/               اختبارات مستضافة في التطبيق
BunnListUITests/             اختبارات واجهة على المحاكي
docs/                        المرجع، المهام، القرارات، التحقق، مراجعة المخطط، خريطة البيانات
```

## التشغيل

```sh
bash scripts/test-core.sh                                   # Core على Linux أو macOS
mint run yonaskolb/XcodeGen@2.42.0 xcodegen generate        # على macOS فقط
open BunnList.xcodeproj                                     # مخطط BunnList، محاكي iPhone
```

التفاصيل والاختبارات المطلوبة قبل إغلاق C01: [`docs/mac-verification.md`](docs/mac-verification.md).

## المنفذ في C01

- **التنقل:** اكتشف (بحث ومرشحات)، مجموعتي، مسح، المجتمع (موسوم غير متاح)، حسابي (زائر).
- **المنتج والدفعة:** كل منتج له مواسم مستقلة ودفعة «الموسم غير معروف» مشتركة. لا تخمين للموسم.
- **المجموعة:** لديّ، جربته، مفضل، ودي أجرب، حالات مستقلة. الإزالة لا تمحو التاريخ.
- **«هل هو نفس الكيس؟»** عند جمع موسم محدد بعد «غير معروف» أو العكس، و«حدّد موسم سجلي» لنقل السجل.
- **المسح:** كاميرا حقيقية مع فحص العتاد قبل الإذن، واختيار صورة، وإدخال يدوي، ثم مراجعة قابلة للتعديل ومطابقة. القراءة نفسها تجريبية لا تقرأ الصورة.
- **الحفظ:** SwiftData على الجهاز، ولا يظهر أي تغيير قبل نجاح حفظه.

## الشعار

ملف `bunnlist_symbol_transparent.png` الأصلي غير موجود في المستودع. أضفه إلى مجموعة `BunnListSymbol` في `BunnList/Resources/Assets.xcassets` دون تعديل. أيقونة التطبيق (1024×1024 RGB على #EDE3D6، الرمز ≤70% من العرض) تُنتج منه لاحقًا؛ مجموعة `AppIcon` فارغة حاليًا، فالنسخة غير جاهزة للتوزيع.
