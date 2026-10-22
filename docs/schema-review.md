# مراجعة مخطط الخادم (C00)

المصدر: `Dev-Mohd/bunnlist` (الالتزام `e56cc1c`)، الملف `prisma/schema.prisma` وقائمة `prisma/migrations` (6 ترحيلات من 20260518 إلى 20260522). **قراءة الملفات فقط.** لا يوجد اتصال قراءة بقاعدة الإنتاج، فمطابقة المخطط الفعلي للإنتاج **غير متحققة** وتبقى بوابة C03.

## ما يطابق عقد التطبيق

| المستودع | Core | ملاحظة |
|---|---|---|
| `OriginCountry.isoCode` | `Origin.countryCodes` (ISO) | مطابق |
| `enum CoffeeProcess` | `ReferenceCodes.processes` | نفس الأكواد الثمانية |
| `enum BrewMethod` | `ReferenceCodes.brewMethods` | نفس الأكواد السبعة |
| `Roaster` (name, nameAr) | `Roaster` (nameEn, nameAr) | |
| معرفات `cuid()` | `OpaqueID` | معرف الخادم سلسلة معتمة؛ لا تحليل لصيغته |
| `Review @@unique([coffeeLotId, userId])` | تقييم واحد لكل مستخدم ودفعة | مرشح للبقاء كتقييم المحصول |

## فجوات تحتاج ترحيلًا في C03 (لا تُنفذ الآن)

1. **لا يوجد `CoffeeProduct`.** `CoffeeLot` الحالي يجمع الهوية التسويقية والموسم. المرجع يمنع اعتباره منتجًا أمًا بلا مراجعة؛ خطة الترحيل في C03 تنشئ منتجًا لكل دفعة حالية مع UNKNOWN، ثم تُراجع الدمج يدويًا.
2. **لا موسم ولا UNKNOWN:** لا `seasonLabel` أو `harvestYear` أو نوع دفعة.
3. **المنشأ بلد واحد إلزامي** (`originCountryId`)، فلا يمثل الخلطات (`MULTI_COUNTRY`) ولا المجهول.
4. **`Review` يخلط التقييم بالتجربة:** يحمل `brewMethod` و`wouldBuyAgain` و`body`. التجارب كيان مستقل في المرجع؛ لا تحوَّل المراجعات التاريخية إلى تجارب تلقائيًا.
5. **لا اعتماد للدفعات:** `publishedAt` فقط، بلا حالة pending/approved/rejected.
6. **`flavorNotes String[]`** نص حر، لا أكواد `FlavorDescriptor`.
7. **غائب:** `CollectionEntry` و`clientId` وقيود `(ownerId, clientId)` و`IdempotencyRecord` و`ClientCreationKey` وكل كيانات المجتمع والنقاط.
8. **المصادقة:** Auth.js (`Account`, `Session`, `VerificationToken`) للويب. يوجد `lib/apple-secret.ts`، لكن ذلك لا يعني جاهزية دخول الجوال (جلسات مدورة وKeychain وإبطال رموز Apple).
9. **المتوسطات المخزنة** (`averageRating`, `reviewCount`, `CoffeeLotBrewStat`) تحتاج إعادة تعريف: متوسط الدفعة من التقييمات المنشورة فقط، وإحصاءات الطرق بالأفراد.

## عقد DTO المبدئي

حتى C03، Core هو العقد: `Catalog`/`CoffeeProduct`/`CoffeeLot`/`LotSeason`/`Origin` كما في `Packages/BunnListCore/Sources/BunnListCore/Catalog.swift`، وترميز JSON في `fixtures.json`. `LotSeason` يُرمَّز كـ`{"known":{"label":…,"harvestYear":…}}` أو `{"unknown":{}}`.

لا يُدّعى تطابق الإنتاج. لم يُقرأ أي صف مستخدمين، ولم تُستخرج أسرار، ولم يُشغّل `seed` أو `migrate`.
