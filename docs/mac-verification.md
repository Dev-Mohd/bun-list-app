# بوابة Mac/المحاكي

تُشغَّل على Mac قبل إغلاق C00 وC01. لا تحتاج حساب مطور مدفوعًا ولا أسرار توقيع.

## المتطلبات

- macOS مع Xcode 16.2 أو أحدث (Swift 6.0.3+) ومحاكي iOS 17 أو أحدث.
- XcodeGen 2.42.0: `brew install mint && mint install yonaskolb/XcodeGen@2.42.0`

## الأوامر

```sh
# 1) اختبارات Core
bash scripts/test-core.sh

# 2) توليد المشروع
mint run yonaskolb/XcodeGen@2.42.0 xcodegen generate

# 3) وجهة محاكي متاحة
xcodebuild -showdestinations -project BunnList.xcodeproj -scheme BunnList
# استبدل SIMULATOR_UDID بمعرف iPhone من القائمة.

# 4) البناء
xcodebuild -project BunnList.xcodeproj -scheme BunnList \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

# 5) الاختبارات (وحدة + واجهة)
xcodebuild -project BunnList.xcodeproj -scheme BunnList \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
```

## ما تتحقق منه الاختبارات

| الهدف | الاختبار |
|---|---|
| BunnListTests | وجود `NSCameraUsageDescription` في التطبيق المبني وتعريبه في `ar.lproj` و`en.lproj`؛ تحميل الدليل التجريبي؛ حفظ SwiftData واستعادته من حاوية جديدة على القرص (محاكاة إعادة التشغيل)؛ جسر الفاصلة حسب المنطقة؛ سؤال «نفس الكيس» وفشل الحفظ في `AppModel` |
| BunnListUITests | حالة «لا كاميرا» بلا رابط إعدادات؛ حالة رفض الإذن منفصلة؛ إدخال يدوي ← مطابقة ← جمع «الموسم غير معروف» ← ظهوره في «مجموعتي» |

اختبارات الواجهة تشغّل التطبيق بـ`-uiTesting` (تخزين في الذاكرة)، فلا تمس بيانات المحاكي.

## مراجعة يدوية على المحاكي

- iPhone SE وiPhone كبير، فاتح وداكن: لا قص للعربية، والتبويبات بالترتيب الصحيح من اليمين.
- أكبر حجم Accessibility: صفحة المنتج ونموذج المراجعة في المسح قابلة للتمرير، والأزرار غير مغطاة بلوحة المفاتيح أو الشريط.
- VoiceOver: أسماء التبويبات والأزرار والمفاتيح، وحوار «هل هو نفس الكيس؟».
- اجمع «الموسم غير معروف» لغوجي، ثم «حصاد ٢٠٢٥»: يظهر السؤال؛ «نعم» ينقل السجل، «لا» يضيف كيسًا مستقلًا، «إلغاء» لا يغير شيئًا.
- أنهِ التطبيق وأعد فتحه: المجموعة وحالاتها باقية.

## سجّل النتيجة

أضف إلى `docs/VALIDATION.md`: إصدار Xcode، اسم المحاكي ومعرفه، ونتيجة كل أمر كما ظهرت. لا تسجل نجاحًا لأمر لم يُشغّل.

## CAM-DEVICE (لاحقًا، شرط C05)

على آيفون فعلي: اختر فريق التوقيع في Xcode محليًا، ثم اختبر طلب الإذن والالتقاط والرفض والاستعادة من الإعدادات. لا ترسل مفاتيح التوقيع لأي محادثة.
