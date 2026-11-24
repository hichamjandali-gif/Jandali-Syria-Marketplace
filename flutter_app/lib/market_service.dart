import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const marketCategories = <MarketCategory>[
  MarketCategory('houses','عقارات: بيع وإيجار','🏠','بيوت وشقق وأراضٍ ومزارع'),
  MarketCategory('cars','سيارات للبيع','🚗','سيارات وموتورات'),
  MarketCategory('free','أغراض مجاناً','🎁','ببلاش - خذ مجاناً'),
  MarketCategory('jobs','وظائف','💼','مطلوب عامل / أبحث عن عمل'),
  MarketCategory('clothes','ملابس','👕','رجالي ونسائي'),
  MarketCategory('phones','جوالات','📱','جوالات وتابلت'),
  MarketCategory('animals','حيوانات','🐄','مواشي وطيور'),
  MarketCategory('services','معلمين وخدمات','🔨','نجار، حداد، صحية'),
  MarketCategory('furniture','أثاث منزلي','🪑','غرف نوم، كنب، طاولات وكراسي'),
  MarketCategory('bikes','دراجات نارية','🏍️','موتورات وسكوترات'),
  MarketCategory('kitchen','أدوات مطبخ','🍳','طناجر وصحون'),
];

class MarketCategory {
  final String id,name,emoji,subtitle;
  const MarketCategory(this.id,this.name,this.emoji,this.subtitle);
  static MarketCategory byId(String id)=>marketCategories.firstWhere((c)=>c.id==id,orElse:()=>marketCategories.first);
}

class MarketListing {
  final String id,ownerId,title,description,category,city,currency,status;
  final String? district,phone;
  final num? price;
  final double? lat,lng;
  final List<String> photos;
  final DateTime? createdAt;
  const MarketListing({required this.id,required this.ownerId,required this.title,required this.description,required this.category,required this.city,required this.currency,required this.status,required this.photos,this.district,this.phone,this.price,this.lat,this.lng,this.createdAt});
  factory MarketListing.fromMap(Map<String,dynamic> m)=>MarketListing(
    id:m['id'] as String,ownerId:m['owner_id'] as String,title:(m['title']??'') as String,
    description:(m['description']??'') as String,category:(m['category']??'houses') as String,
    city:(m['city']??'') as String,district:m['district'] as String?,phone:m['contact_phone'] as String?,
    price:m['price'] as num?,lat:(m['lat'] as num?)?.toDouble(),lng:(m['lng'] as num?)?.toDouble(),currency:(m['currency']??'SYP') as String,status:(m['status']??'active') as String,
    photos:(m['photo_urls'] as List? ?? []).whereType<String>().toList(),
    createdAt:DateTime.tryParse('${m['created_at']??''}'));
  String get location=>[city,district].where((x)=>x!=null&&x.trim().isNotEmpty).join(' - ');
  String get priceLabel=>price==null?'حسب الاتفاق':price==0?'مجاناً':'${price!.toStringAsFixed(0)} ${currency=='USD'?r'$':'ل.س'}';
}

class MarketService {
  MarketService._();
  static final instance=MarketService._();
  SupabaseClient get db=>Supabase.instance.client;
  User? get user=>db.auth.currentUser;
  final _uuid=const Uuid();

  Future<List<MarketListing>> loadListings({String? category,String? city,String query='',int offset=0,int limit=200}) async {
    var req=db.from('market_listings').select().eq('status','active');
    if(category!=null&&category.isNotEmpty) req=req.eq('category',category);
    if(city!=null&&city.trim().isNotEmpty) req=req.ilike('city','%${city.trim()}%');
    final r=await req.order('created_at',ascending:false).range(offset, offset + limit - 1);
    final items=r.map((e)=>MarketListing.fromMap(e)).toList();
    final q=query.trim().toLowerCase();
    if(q.isEmpty)return items;
    return items.where((x)=>'${x.title} ${x.description} ${x.city} ${x.district??''}'.toLowerCase().contains(q)).toList();
  }

  Future<List<MarketListing>> myListings() async {
    final u=user;if(u==null)throw Exception('سجّل الدخول أولاً');
    final r=await db.from('market_listings').select().eq('owner_id',u.id).order('created_at',ascending:false);
    return r.map((e)=>MarketListing.fromMap(e)).toList();
  }

  Future<String> publish({required String title,required String description,required String category,required String city,String? district,String? phone,num? price,required String currency,required List<Uint8List> photoBytes,required List<String> photoNames,required double lat,required double lng}) async {
    final u=user;if(u==null)throw Exception('سجّل الدخول قبل نشر الإعلان');
    if(title.trim().isEmpty||city.trim().isEmpty)throw Exception('أدخل عنوان الإعلان والمدينة');
    if(photoBytes.isEmpty)throw Exception('أضف صورة واحدة على الأقل');
    final id=_uuid.v4(),storage=db.storage.from('market-photos'),paths=<String>[],urls=<String>[];
    try {
      // Ordered upload: the first selected image is the cover at photo_urls[0].
      for(var i=0;i<photoBytes.length;i++){
        final bytes=photoBytes[i],original=photoNames[i];
        final match=RegExp(r'\.(jpe?g|png|webp|heic|heif|gif|bmp|tiff?)(?:$|[._])',caseSensitive:false).firstMatch(original);
        final ext=(match?.group(1)??'jpg').toLowerCase();
        final path=u.id+'/'+id+'/'+i.toString().padLeft(2,'0')+'_'+_uuid.v4()+'.'+ext;
        final mime=lookupMimeType(original,headerBytes:bytes)??
            (ext=='heic'?'image/heic':ext=='heif'?'image/heif':'application/octet-stream');
        await storage.uploadBinary(path,bytes,fileOptions:FileOptions(contentType:mime,upsert:false));
        paths.add(path);urls.add(storage.getPublicUrl(path));
      }
      final row=<String,dynamic>{
        'id':id,'owner_id':u.id,'title':title.trim(),
        'description':description.trim().isEmpty?title.trim():description.trim(),
        'category':category,'city':city.trim(),'lat':lat,'lng':lng,
        'district':district?.trim().isEmpty==true?null:district?.trim(),
        'contact_phone':phone?.trim().isEmpty==true?null:phone?.trim(),
        'price':category=='free'?0:price,'currency':currency,'photo_urls':urls,
      };
      final saved=await db.from('market_listings').insert(row).select('id').single();
      return saved['id'] as String;
    } catch (_) {
      if(paths.isNotEmpty){try{await storage.remove(paths);}catch(_){}}
      rethrow;
    }
  }

  String? _marketPhotoStoragePath(String publicUrl) {
    final uri = Uri.tryParse(publicUrl);
    if (uri == null) return null;
    const marker = '/storage/v1/object/public/market-photos/';
    final index = uri.path.indexOf(marker);
    if (index < 0) return null;
    return Uri.decodeComponent(uri.path.substring(index + marker.length));
  }

  Future<void> updateListing({
    required String id,
    required String title,
    required String description,
    required String city,
    String? district,
    String? phone,
    num? price,
    required String currency,
    required List<String> originalPhotoUrls,
    required List<int> photoOrder,
    required List<Uint8List> newPhotoBytes,
    required List<String> newPhotoNames,
  }) async {
    final u = user;
    if (u == null) throw Exception('سجّل الدخول');
    if (title.trim().isEmpty || city.trim().isEmpty) throw Exception('أدخل عنوان الإعلان والمدينة');
    if (photoOrder.isEmpty || photoOrder.length > 8) throw Exception('يجب اختيار صورة واحدة على الأقل وبحد أقصى 8 صور');
    if (newPhotoBytes.length != newPhotoNames.length) throw Exception('بيانات الصور غير مكتملة');

    final storage = db.storage.from('market-photos');
    final uploadedPaths = <String>[];
    final orderedUrls = <String>[];
    try {
      for (var position = 0; position < photoOrder.length; position++) {
        final token = photoOrder[position];
        if (token >= 0) {
          if (token >= originalPhotoUrls.length) throw Exception('ترتيب الصور غير صالح');
          orderedUrls.add(originalPhotoUrls[token]);
          continue;
        }
        final newIndex = -token - 1;
        if (newIndex < 0 || newIndex >= newPhotoBytes.length) throw Exception('مرجع الصورة الجديدة غير صالح');
        final bytes = newPhotoBytes[newIndex];
        final original = newPhotoNames[newIndex];
        final match = RegExp(r'\.(jpe?g|png|webp|heic|heif|gif|bmp|tiff?)(?:$|[._])', caseSensitive:false).firstMatch(original);
        final ext = (match?.group(1) ?? 'jpg').toLowerCase();
        final path = u.id + '/' + id + '/' + position.toString().padLeft(2, '0') + '_' + _uuid.v4() + '.' + ext;
        final mime = lookupMimeType(original, headerBytes: bytes) ??
            (ext == 'heic' ? 'image/heic' : ext == 'heif' ? 'image/heif' : 'application/octet-stream');
        await storage.uploadBinary(path, bytes, fileOptions: FileOptions(contentType:mime, upsert:false));
        uploadedPaths.add(path);
        orderedUrls.add(storage.getPublicUrl(path));
      }

      final keptExisting = orderedUrls.toSet();
      final removedUrls = originalPhotoUrls.where((url) => !keptExisting.contains(url)).toList();
      final saved = await db.from('market_listings').update({
        'title':title.trim(),
        'description':description.trim().isEmpty?title.trim():description.trim(),
        'city':city.trim(),
        'district':district?.trim().isEmpty==true?null:district?.trim(),
        'contact_phone':phone?.trim().isEmpty==true?null:phone?.trim(),
        'price':price,
        'currency':currency,
        'photo_urls':orderedUrls,
      }).eq('id',id).eq('owner_id',u.id).select('id').maybeSingle();
      if (saved == null) throw Exception('لم يتم العثور على الإعلان أو لا تملك صلاحية تعديله');

      // Delete only images explicitly removed in the editor, and only after the listing update succeeds.
      final removedPaths = removedUrls.map(_marketPhotoStoragePath).whereType<String>().toList();
      if (removedPaths.isNotEmpty) {
        try { await storage.remove(removedPaths); } catch (_) { /* Keep the saved listing if storage cleanup fails. */ }
      }
    } catch (_) {
      if (uploadedPaths.isNotEmpty) {
        try { await storage.remove(uploadedPaths); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> closeListing(String id) async {
    final u=user;if(u==null)throw Exception('سجّل الدخول');
    await db.from('market_listings').update({'status':'closed'}).eq('id',id).eq('owner_id',u.id);
  }
  Future<void> deleteListing(String id) async {
    final u=user;if(u==null)throw Exception('سجّل الدخول');
    await db.from('market_listings').delete().eq('id',id).eq('owner_id',u.id);
  }
  Future<String> openConversation(MarketListing listing) async {
    final u=user;if(u==null)throw Exception('سجّل الدخول للمراسلة');
    if(listing.ownerId==u.id)throw Exception('هذا إعلانك');
    final old=await db.from('market_conversations').select('id').eq('listing_id',listing.id).eq('buyer_id',u.id).maybeSingle();
    if(old!=null)return old['id'] as String;
    final r=await db.from('market_conversations').insert({'listing_id':listing.id,'buyer_id':u.id,'seller_id':listing.ownerId}).select('id').single();
    return r['id'] as String;
  }
  Future<String> conversationTitle(Map<String,dynamic> conversation) async {
    final listingId=conversation['listing_id'];
    if(listingId==null)return 'محادثة خاصة';
    final row=await db.from('market_listings').select('title,city').eq('id',listingId).maybeSingle();
    if(row==null)return 'إعلان غير متاح';
    final title=(row['title']??'إعلان').toString();
    final city=(row['city']??'').toString();
    return city.isEmpty?title:'$title • $city';
  }

  Future<List<Map<String,dynamic>>> conversations() async {
    final u=user;if(u==null)throw Exception('سجّل الدخول');
    final r=await db.from('market_conversations').select().or('buyer_id.eq.${u.id},seller_id.eq.${u.id}').order('created_at',ascending:false);
    return r.cast<Map<String,dynamic>>();
  }
  Future<List<Map<String,dynamic>>> messages(String id) async {
    final r=await db.from('market_messages').select().eq('conversation_id',id).order('created_at',ascending:true).limit(200);
    return r.cast<Map<String,dynamic>>();
  }
  Future<void> sendMessage(String id,String body) async {
    final u=user;if(u==null)throw Exception('سجّل الدخول');
    final text=body.trim();if(text.isEmpty)return;
    await db.from('market_messages').insert({'conversation_id':id,'sender_id':u.id,'body':text});
    
  }
}
