import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  
  await BildirimServisi.init();

  final prefs = await SharedPreferences.getInstance();
  bool beniHatirla = prefs.getBool('beni_hatirla') ?? false;
  User? currentUser = FirebaseAuth.instance.currentUser;

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('tr', 'TR')],
    home: (beniHatirla && currentUser != null) ? const AnaSayfaYoneticisi() : const GirisEkrani(),
  ));
}

Future<void> cikisYap(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('beni_hatirla', false);
  if (context.mounted) {
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const GirisEkrani()), (r) => false);
  }
}

class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});
  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  bool kayitOlMode = false;
  final TextEditingController eposta = TextEditingController();
  final TextEditingController sifre = TextEditingController();
  bool yukleniyor = false;

  Future<void> _islemYap() async {
    if (eposta.text.isEmpty || sifre.text.isEmpty) return;
    setState(() => yukleniyor = true);
    try {
      if (kayitOlMode) {
        UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: eposta.text.trim(), password: sifre.text.trim());
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProfilTamamlamaEkrani(user: cred.user!)));
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: eposta.text.trim(), password: sifre.text.trim());
            
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('kullanicilar').doc(FirebaseAuth.instance.currentUser!.uid).set({'fcmToken': token}, SetOptions(merge: true));
        }
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('beni_hatirla', true);

        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AnaSayfaYoneticisi()));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hata! Bilgilerinizi kontrol edin.'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.local_car_wash, size: 90, color: Colors.blueAccent),
              const SizedBox(height: 20),
              Text(kayitOlMode ? 'Müşteri Kayıt' : 'Müşteri Girişi', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              TextField(controller: eposta, decoration: InputDecoration(labelText: 'E-Posta', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.email))),
              const SizedBox(height: 16),
              TextField(controller: sifre, obscureText: true, decoration: InputDecoration(labelText: 'Şifre', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.lock))),
              const SizedBox(height: 24),
              yukleniyor ? const Center(child: CircularProgressIndicator()) : ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _islemYap,
                child: Text(kayitOlMode ? 'Kayıt Ol' : 'Giriş Yap', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => kayitOlMode = !kayitOlMode),
                child: Text(kayitOlMode ? 'Zaten hesabın var mı? Giriş yap' : 'Hesabın yok mu? Kayıt ol', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class ProfilTamamlamaEkrani extends StatefulWidget {
  final User user;
  const ProfilTamamlamaEkrani({super.key, required this.user});

  @override
  State<ProfilTamamlamaEkrani> createState() => _ProfilTamamlamaEkraniState();
}

class _ProfilTamamlamaEkraniState extends State<ProfilTamamlamaEkrani> {
  final TextEditingController ad = TextEditingController();
  final TextEditingController tel = TextEditingController();
  
  File? _secilenFoto;
  bool _yukleniyor = false;

  Future<void> _fotografSec(ImageSource kaynak) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: kaynak, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _secilenFoto = File(pickedFile.path);
      });
    }
  }

  void _fotografSecenekleriniGoster() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Seç'),
              onTap: () {
                Navigator.pop(context);
                _fotografSec(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kameradan Çek'),
              onTap: () {
                Navigator.pop(context);
                _fotografSec(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _kaydiTamamla() async {
    if (ad.text.trim().isEmpty || tel.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen ad soyad ve telefon alanlarını doldurun.')));
      return;
    }

    setState(() => _yukleniyor = true);

    try {
      String fotoUrl = '';
      if (_secilenFoto != null) {
        Reference ref = FirebaseStorage.instance.ref().child('profil_fotolari_musteri').child('${widget.user.uid}.jpg');
        await ref.putFile(_secilenFoto!);
        fotoUrl = await ref.getDownloadURL();
      }

      String? token = await FirebaseMessaging.instance.getToken();
      await FirebaseFirestore.instance.collection('kullanicilar').doc(widget.user.uid).set({
        'uid': widget.user.uid,
        'adSoyad': ad.text.trim(),
        'telefon': tel.text.trim(),
        'profilFoto': fotoUrl,
        'rol': 'musteri',
        'fcmToken': token ?? '',
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('beni_hatirla', true);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AnaSayfaYoneticisi()));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata oluştu: $e')));
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Müşteri Profil Tamamlama'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: _secilenFoto != null ? FileImage(_secilenFoto!) : null,
                    child: _secilenFoto == null ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _fotografSecenekleriniGoster,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(controller: ad, decoration: InputDecoration(labelText: 'Ad Soyad', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 16),
            TextField(controller: tel, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Telefon Numarası', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 24),
            _yukleniyor
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _kaydiTamamla,
                    child: const Text('Kaydı Tamamla', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  )
          ],
        ),
      ),
    );
  }
}

class AnaSayfaYoneticisi extends StatefulWidget {
  const AnaSayfaYoneticisi({super.key});
  @override
  State<AnaSayfaYoneticisi> createState() => _AnaSayfaYoneticisiState();
}

class _AnaSayfaYoneticisiState extends State<AnaSayfaYoneticisi> {
  int _secilenIndex = 0;
  final List<Widget> _sayfalar = [
    const IlanOlusturEkrani(), 
    const AktifIlanlarEkrani(),
    const GecmisIlanlarEkrani(),
    const ProfilSekmesiEkrani(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _sayfalar[_secilenIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _secilenIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        onTap: (i) => setState(() => _secilenIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Ana Sayfa'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Aktif İlanlar'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Geçmiş'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class IlanOlusturEkrani extends StatelessWidget {
  const IlanOlusturEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hizmetlerimiz', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey.shade100,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ne yaptırmak istersiniz?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _kareButon(context, 'Aracını Anında\nYıkat 🚀', Icons.bolt, Colors.orange, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AnindaYikamaBilgiEkrani()));
                  }),
                  _kareButon(context, 'Kapıda Araba\nYıkama', Icons.edit_calendar, Colors.blueAccent, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RandevuBilgiEkrani()));
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kareButon(BuildContext context, String baslik, IconData icon, Color renk, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6)]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: renk.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 36, color: renk)),
            const SizedBox(height: 12),
            Text(baslik, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// PROFİL SEKME VE ALT EKRANLARI
// ==========================================
class ProfilSekmesiEkrani extends StatefulWidget {
  const ProfilSekmesiEkrani({super.key});

  @override
  State<ProfilSekmesiEkrani> createState() => _ProfilSekmesiEkraniState();
}

class _ProfilSekmesiEkraniState extends State<ProfilSekmesiEkrani> {
  bool _fotoYukleniyor = false;

  Future<void> _fotografGuncelle(ImageSource kaynak) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: kaynak, imageQuality: 70);
    
    if (pickedFile != null) {
      setState(() => _fotoYukleniyor = true);
      try {
        User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          File secilenFoto = File(pickedFile.path);
          Reference ref = FirebaseStorage.instance.ref().child('profil_fotolari_musteri').child('${user.uid}.jpg');
          
          await ref.putFile(secilenFoto);
          String fotoUrl = await ref.getDownloadURL();
          
          await FirebaseFirestore.instance.collection('kullanicilar').doc(user.uid).update({
            'profilFoto': fotoUrl,
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil fotoğrafınız güncellendi! ✅'), backgroundColor: Colors.green));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fotoğraf güncellenirken hata oluştu: $e'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _fotoYukleniyor = false);
      }
    }
  }

  void _fotografSecenekleriniGoster() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Seç'),
              onTap: () {
                Navigator.pop(context);
                _fotografGuncelle(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kameradan Çek'),
              onTap: () {
                Navigator.pop(context);
                _fotografGuncelle(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Oturum açılmamış.'));

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Profil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('kullanicilar').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          String adSoyad = 'Kullanıcı';
          String? profilFotoUrl;

          if (snapshot.hasData && snapshot.data!.exists) {
            var data = snapshot.data!.data() as Map<String, dynamic>;
            adSoyad = data['adSoyad'] ?? 'Kullanıcı';
            profilFotoUrl = data['profilFoto'];
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _fotografSecenekleriniGoster,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundColor: Colors.blue.shade50,
                              backgroundImage: (profilFotoUrl != null && profilFotoUrl.isNotEmpty) ? NetworkImage(profilFotoUrl) : null,
                              child: (profilFotoUrl == null || profilFotoUrl.isEmpty)
                                  ? const Icon(Icons.person, size: 35, color: Colors.blueAccent)
                                  : null,
                            ),
                            if (_fotoYukleniyor)
                              const CircularProgressIndicator(color: Colors.white),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blueAccent),
                                child: const Icon(Icons.edit, color: Colors.white, size: 14),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Merhaba 👋', style: TextStyle(fontSize: 16, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(adSoyad, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.support_agent, color: Colors.purple),
                        title: const Text('Destek Merkezi', style: TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: const Text('Taleplerim ve yanıtlar', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const DestekTalepleriEkrani()));
                        },
                      ),
                      const Divider(height: 1, indent: 50),
                      ListTile(
                        leading: const Icon(Icons.settings, color: Colors.blueAccent),
                        title: const Text('Hesap Ayarları', style: TextStyle(fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const HesapAyarlariEkrani()));
                        },
                      ),
                      const Divider(height: 1, indent: 50),
                      ListTile(
                        leading: const Icon(Icons.notifications_active, color: Colors.orange),
                        title: const Text('İletişim Tercihleri', style: TextStyle(fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const IletisimTercihleriEkrani()));
                        },
                      ),
                      const Divider(height: 1, indent: 50),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip, color: Colors.green),
                        title: const Text('Gizlilik Politikası', style: TextStyle(fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const GizlilikPolitikasiEkrani()));
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.red, width: 1.5),
                    ),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Çıkış Yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext ctx) {
                        return AlertDialog(
                          title: const Text("Çıkış Yap"),
                          content: const Text("Hesabınızdan çıkış yapmak istediğinize emin misiniz?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                cikisYap(context);
                              }, 
                              child: const Text("Çıkış Yap", style: TextStyle(color: Colors.red))
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}

// ==========================================
// DESTEK: TALEP LİSTESİ (Müşteri kendi taleplerini ve durumlarını görür)
// ==========================================
class DestekTalepleriEkrani extends StatelessWidget {
  const DestekTalepleriEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Destek Taleplerim'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Talep'),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DestekEkrani()));
        },
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('destek_talepleri')
            .where('uid', isEqualTo: user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;

          // En yeni talep en üstte görünsün
          docs.sort((a, b) {
            var aData = a.data() as Map<String, dynamic>;
            var bData = b.data() as Map<String, dynamic>;
            String aZaman = (aData['zaman'] ?? '').toString();
            String bZaman = (bData['zaman'] ?? '').toString();
            return bZaman.compareTo(aZaman);
          });

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.support_agent, size: 70, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'Henüz bir destek talebiniz yok.\nSağ alttaki butondan yeni talep oluşturabilirsiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              bool yanitlandi = data['durum'] == 'yanitlandi' &&
                  (data['yanit'] ?? '').toString().trim().isNotEmpty;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: (yanitlandi ? Colors.green : Colors.orange).withOpacity(0.1),
                    child: Icon(
                      yanitlandi ? Icons.mark_email_read : Icons.hourglass_top,
                      color: yanitlandi ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(
                    (data['konu'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      (data['mesaj'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (yanitlandi ? Colors.green : Colors.orange).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      yanitlandi ? 'YANITLANDI' : 'BEKLİYOR',
                      style: TextStyle(
                        color: yanitlandi ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DestekDetayEkrani(talepId: docs[index].id)),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// DESTEK: TALEP DETAYI (Mesaj + varsa admin yanıtı, canlı olarak izlenir)
// ==========================================
class DestekDetayEkrani extends StatelessWidget {
  final String talepId;
  const DestekDetayEkrani({super.key, required this.talepId});

  String _zamanFormatla(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      DateTime dt = DateTime.parse(raw);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Talep Detayı'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        // talep dokümanını canlı dinliyoruz; admin Firebase Console'dan
        // 'yanit' / 'durum' alanlarını güncellediği an burası otomatik yenilenir.
        stream: FirebaseFirestore.instance.collection('destek_talepleri').doc(talepId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) {
            return const Center(child: Text('Bu talep bulunamadı veya silinmiş olabilir.'));
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          bool yanitlandi = data['durum'] == 'yanitlandi' &&
              (data['yanit'] ?? '').toString().trim().isNotEmpty;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              (data['konu'] ?? '').toString(),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (yanitlandi ? Colors.green : Colors.orange).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              yanitlandi ? 'YANITLANDI' : 'BEKLİYOR',
                              style: TextStyle(
                                color: yanitlandi ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_zamanFormatla(data['zaman']), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Divider(height: 24),
                      Text(
                        (data['mesaj'] ?? '').toString(),
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (yanitlandi) ...[
                  Row(
                    children: const [
                      Icon(Icons.support_agent, color: Colors.blueAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Destek Ekibi Yanıtı', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (data['yanit'] ?? '').toString(),
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
                        if ((data['yanitZamani'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(_zamanFormatla(data['yanitZamani']), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ]
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.hourglass_top, color: Colors.orange),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Talebiniz destek ekibimize ulaştı. Yanıtlandığında burada görüntülenecek.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              ],
            ),
          );
        },
      ),
    );
  }
}

class DestekEkrani extends StatefulWidget {
  const DestekEkrani({super.key});

  @override
  State<DestekEkrani> createState() => _DestekEkraniState();
}

class _DestekEkraniState extends State<DestekEkrani> {
  final TextEditingController konuController = TextEditingController();
  final TextEditingController mesajController = TextEditingController();
  bool _yukleniyor = false;

  Future<void> _destekTalebiGonder() async {
    if (konuController.text.trim().isEmpty || mesajController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen konu ve mesaj alanlarını eksiksiz doldurun.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _yukleniyor = true);

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('destek_talepleri').add({
        'uid': user.uid,
        'eposta': user.email ?? 'Belirtilmemiş',
        'konu': konuController.text.trim(),
        'mesaj': mesajController.text.trim(),
        'durum': 'bekliyor',
        'yanit': '',
        'yanitZamani': '',
        'zaman': DateTime.now().toString(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Talebiniz başarıyla iletildi! En kısa sürede dönüş yapacağız. ✅'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Talebiniz gönderilirken hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Destek Talebi'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.support_agent, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 16),
            const Text(
              'Size nasıl yardımcı olabiliriz?\nLütfen sorununuzu aşağıya detaylıca yazın.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 32),
            const Text('Konu:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: konuController,
              decoration: InputDecoration(
                hintText: 'Örn: Ödeme Hatası, Randevu İptali...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Yaşadığınız problemi bizlere iletin:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: mesajController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Mesajınızı buraya yazın...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            _yukleniyor
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text('Talebi Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: _destekTalebiGonder,
                  )
          ],
        ),
      ),
    );
  }
}

class HesapAyarlariEkrani extends StatefulWidget {
  const HesapAyarlariEkrani({super.key});

  @override
  State<HesapAyarlariEkrani> createState() => _HesapAyarlariEkraniState();
}

class _HesapAyarlariEkraniState extends State<HesapAyarlariEkrani> {
  final TextEditingController sifreController = TextEditingController();
  bool yukleniyor = false;

  Future<void> _ayarlariKaydet() async {
    setState(() => yukleniyor = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (sifreController.text.trim().isNotEmpty) {
        await user.updatePassword(sifreController.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şifreniz başarıyla güncellendi! ✅'), backgroundColor: Colors.green));
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Herhangi bir değişiklik yapılmadı.'), backgroundColor: Colors.orange));
          Navigator.pop(context);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: ${e.message}'), backgroundColor: Colors.red));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bir hata oluştu: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hesap Ayarları'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Yeni Şifre Belirle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: sifreController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Şifreyi değiştirmek istemiyorsanız boş bırakın',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.lock)
              ),
            ),
            const SizedBox(height: 32),
            yukleniyor ? const Center(child: CircularProgressIndicator()) : ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent, 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              onPressed: _ayarlariKaydet,
              child: const Text('Değişiklikleri Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

class IletisimTercihleriEkrani extends StatefulWidget {
  const IletisimTercihleriEkrani({super.key});

  @override
  State<IletisimTercihleriEkrani> createState() => _IletisimTercihleriEkraniState();
}

class _IletisimTercihleriEkraniState extends State<IletisimTercihleriEkrani> {
  bool _bildirimlerAcik = true;

  @override
  void initState() {
    super.initState();
    _tercihleriYukle();
  }

  Future<void> _tercihleriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bildirimlerAcik = prefs.getBool('bildirimler_acik') ?? true; 
    });
  }

  Future<void> _tercihDegistir(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bildirimler_acik', value);
    setState(() {
      _bildirimlerAcik = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İletişim Tercihleri'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SwitchListTile(
              title: const Text('Uygulama Bildirimleri', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Kampanyalar ve ilan durumu hakkında bildirim alın.'),
              value: _bildirimlerAcik,
              activeColor: Colors.blueAccent,
              onChanged: _tercihDegistir,
            ),
          )
        ],
      ),
    );
  }
}

class GizlilikPolitikasiEkrani extends StatelessWidget {
  const GizlilikPolitikasiEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gizlilik Politikası'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.privacy_tip_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Gizlilik politikası çok yakında bu alana eklenecektir.', 
                textAlign: TextAlign.center, 
                style: TextStyle(fontSize: 16, color: Colors.grey)
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// (DİĞER EKRANLAR: RandevuBilgiEkrani, RandevuKonumEkrani, AnindaYikamaBilgiEkrani, AnindaYikamaCanliHaritaEkrani, CanliTakipEkrani, IlanKartWidget, AktifIlanlarEkrani, GecmisIlanlarEkrani, SohbetEkrani KODLARININ AYNEN BURADA DEVAM ETTİĞİNİ VARSAYIYORUZ)

class RandevuBilgiEkrani extends StatefulWidget {
  const RandevuBilgiEkrani({super.key});
  @override
  State<RandevuBilgiEkrani> createState() => _RandevuBilgiEkraniState();
}

class _RandevuBilgiEkraniState extends State<RandevuBilgiEkrani> {
  final TextEditingController plaka = TextEditingController();
  String aracTipi = 'Sedan';
  DateTime? secilenTarih;
  TimeOfDay? secilenSaat;

  Future<void> _tarihSec() async {
    DateTime yarin = DateTime.now().add(const Duration(days: 1));
    DateTime ucGunSonrasi = DateTime.now().add(const Duration(days: 3));

    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: secilenTarih ?? yarin,
      firstDate: yarin,
      lastDate: ucGunSonrasi,
      helpText: 'Randevu Tarihini Seçin (Maks. 3 Gün İleri)',
    );

    if (picked != null) {
      setState(() => secilenTarih = picked);
    }
  }

  Future<void> _saatSec() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: secilenSaat ?? const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Randevu Saatini Seçin',
    );
    if (picked != null) {
      setState(() => secilenSaat = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    String tarihMetni = secilenTarih == null 
        ? 'Tarih Seçiniz' 
        : '${secilenTarih!.day.toString().padLeft(2, '0')}.${secilenTarih!.month.toString().padLeft(2, '0')}.${secilenTarih!.year}';
        
    String saatMetni = secilenSaat == null 
        ? 'Saat Seçiniz' 
        : '${secilenSaat!.hour.toString().padLeft(2, '0')}:${secilenSaat!.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Randevu Oluştur'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Araç Bilgileri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: aracTipi,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              items: ['Sedan', 'Hatchback', 'SUV', 'Minivan'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() => aracTipi = val!),
            ),
            const SizedBox(height: 16),
            TextField(controller: plaka, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'Plaka (Örn: 10ABC12)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            
            const SizedBox(height: 32),
            const Text('Randevu Zamanı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
              leading: const Icon(Icons.calendar_month, color: Colors.blueAccent),
              title: Text(tarihMetni, style: TextStyle(color: secilenTarih == null ? Colors.grey : Colors.black, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _tarihSec,
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
              leading: const Icon(Icons.access_time, color: Colors.blueAccent),
              title: Text(saatMetni, style: TextStyle(color: secilenSaat == null ? Colors.grey : Colors.black, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _saatSec,
            ),

            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                if (plaka.text.trim().isEmpty || secilenTarih == null || secilenSaat == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen tüm bilgileri eksiksiz doldurun.'), backgroundColor: Colors.red));
                  return;
                }
                Navigator.push(context, MaterialPageRoute(builder: (_) => RandevuKonumEkrani(
                  plaka: plaka.text.trim(), 
                  aracTipi: aracTipi, 
                  tarih: tarihMetni, 
                  saat: saatMetni
                )));
              },
              child: const Text('Konum Seçimine Geç 📍', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

class RandevuKonumEkrani extends StatefulWidget {
  final String plaka, aracTipi, tarih, saat;
  const RandevuKonumEkrani({super.key, required this.plaka, required this.aracTipi, required this.tarih, required this.saat});
  @override
  State<RandevuKonumEkrani> createState() => _RandevuKonumEkraniState();
}

class _RandevuKonumEkraniState extends State<RandevuKonumEkrani> {
  LatLng? _suAnkiKonum;
  bool _yukleniyor = true;
  String _hataMesaji = '';
  
  final TextEditingController sokakController = TextEditingController();
  final TextEditingController binaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gercekKonumuAl();
  }

  Future<void> _gercekKonumuAl() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() { _yukleniyor = false; _hataMesaji = 'Konum (GPS) servisi kapalı.'; });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() { _yukleniyor = false; _hataMesaji = 'Konum izni reddedildi.'; });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() { _yukleniyor = false; _hataMesaji = 'Konum izinleri kalıcı reddedilmiş.'; });
        return;
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _suAnkiKonum = LatLng(position.latitude, position.longitude);
          _yukleniyor = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _yukleniyor = false; _hataMesaji = 'Konum alınamadı: $e'; });
    }
  }

  Future<void> _randevuyuKaydet() async {
    if (sokakController.text.trim().isEmpty || binaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen adres detaylarını doldurun.'), backgroundColor: Colors.red));
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _suAnkiKonum != null) {
      await FirebaseFirestore.instance.collection('ilanlar').add({
        'musteriUid': user.uid,
        'plaka': widget.plaka.toUpperCase(),
        'aracTipi': widget.aracTipi,
        'tarih': widget.tarih,
        'saat': widget.saat,
        'sokak': sokakController.text.trim(),
        'bina': binaController.text.trim(),
        'enlem': _suAnkiKonum!.latitude,
        'boylam': _suAnkiKonum!.longitude,
        'durum': 'bekliyor',
        'isAninda': false,
        'olusturma': DateTime.now().toString(),
      });

      var workers = await FirebaseFirestore.instance.collection('kullanicilar').where('rol', isEqualTo: 'calisan').get();
      for (var worker in workers.docs) {
        await FirebaseFirestore.instance.collection('bildirimler').add({
          'aliciUid': worker.id,
          'baslik': 'Yeni Randevu Talebi! 📅',
          'icerik': '${widget.plaka.toUpperCase()} plakalı araç için ${widget.tarih} - ${widget.saat} zamanına randevu oluşturuldu.',
          'okundu': false,
          'zaman': DateTime.now().toString(),
        });
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AnaSayfaYoneticisi()), (r) => false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Randevunuz başarıyla oluşturuldu! ✅'), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return Scaffold(appBar: AppBar(title: const Text('Konum Bulunuyor'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white), body: const Center(child: CircularProgressIndicator()));
    if (_hataMesaji.isNotEmpty || _suAnkiKonum == null) return Scaffold(appBar: AppBar(title: const Text('Hata'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white), body: Center(child: Text(_hataMesaji)));

    return Scaffold(
      appBar: AppBar(title: const Text('Adres Doğrulama ve Konum'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _suAnkiKonum!, zoom: 16),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
              },
              markers: {Marker(markerId: const MarkerId('konum'), position: _suAnkiKonum!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure))},
              onCameraMove: (position) {
                _suAnkiKonum = position.target;
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(0, -5))]),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Lütfen adresi detaylandırın:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: sokakController, decoration: InputDecoration(labelText: 'Sokak / Cadde', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: binaController, decoration: InputDecoration(labelText: 'Bina / Kapı No', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _randevuyuKaydet,
                    child: const Text('Randevuyu Oluştur ✅', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class AnindaYikamaBilgiEkrani extends StatefulWidget {
  const AnindaYikamaBilgiEkrani({super.key});
  @override
  State<AnindaYikamaBilgiEkrani> createState() => _AnindaYikamaBilgiEkraniState();
}

class _AnindaYikamaBilgiEkraniState extends State<AnindaYikamaBilgiEkrani> {
  final TextEditingController plaka = TextEditingController();
  String aracTipi = 'Sedan';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anında Yıkat - Araç Bilgisi'), backgroundColor: Colors.orange, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: aracTipi,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              items: ['Sedan', 'Hatchback', 'SUV', 'Minivan'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() => aracTipi = val!),
            ),
            const SizedBox(height: 16),
            TextField(controller: plaka, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'Plaka (Örn: 10ABC12)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                if (plaka.text.trim().isNotEmpty) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AnindaYikamaCanliHaritaEkrani(plaka: plaka.text.trim(), aracTipi: aracTipi)));
                }
              },
              child: const Text('Haritada Yıkamacıları Gör 📍', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

class AnindaYikamaCanliHaritaEkrani extends StatefulWidget {
  final String plaka, aracTipi;
  const AnindaYikamaCanliHaritaEkrani({super.key, required this.plaka, required this.aracTipi});
  @override
  State<AnindaYikamaCanliHaritaEkrani> createState() => _AnindaYikamaCanliHaritaEkraniState();
}

class _AnindaYikamaCanliHaritaEkraniState extends State<AnindaYikamaCanliHaritaEkrani> {
  LatLng? _suAnkiKonum;
  bool _yukleniyor = true;
  String _hataMesaji = '';

  @override
  void initState() {
    super.initState();
    _gercekKonumuAl();
  }

  Future<void> _gercekKonumuAl() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() { _yukleniyor = false; _hataMesaji = 'Cihazınızın konum servisi kapalı.'; });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() { _yukleniyor = false; _hataMesaji = 'Konum izni reddedildi.'; });
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) setState(() { _suAnkiKonum = LatLng(position.latitude, position.longitude); _yukleniyor = false; });
    } catch (e) {
      if (mounted) setState(() { _yukleniyor = false; _hataMesaji = 'Konum alınamadı: $e'; });
    }
  }

  Future<void> _ilanGonder() async {
    if (_suAnkiKonum == null) return;
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('ilanlar').add({
        'musteriUid': user.uid,
        'plaka': widget.plaka.toUpperCase(),
        'aracTipi': widget.aracTipi,
        'enlem': _suAnkiKonum!.latitude,
        'boylam': _suAnkiKonum!.longitude,
        'durum': 'bekliyor',
        'isAninda': true,
        'olusturma': DateTime.now().toString(),
      });

      var workers = await FirebaseFirestore.instance.collection('kullanicilar').where('rol', isEqualTo: 'calisan').get();
      for (var worker in workers.docs) {
        await FirebaseFirestore.instance.collection('bildirimler').add({
          'aliciUid': worker.id,
          'baslik': 'Yeni Yıkama Talebi! 🚗',
          'icerik': '${widget.plaka.toUpperCase()} plakalı araç için anında yıkamacı çağrıldı.',
          'okundu': false,
          'zaman': DateTime.now().toString(),
        });
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AnaSayfaYoneticisi()), (r) => false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Talebiniz ustalara iletildi! 🚀'), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) return Scaffold(appBar: AppBar(title: const Text('Konum Bulunuyor'), backgroundColor: Colors.orange, foregroundColor: Colors.white), body: const Center(child: CircularProgressIndicator()));
    if (_hataMesaji.isNotEmpty || _suAnkiKonum == null) return Scaffold(appBar: AppBar(title: const Text('Hata'), backgroundColor: Colors.orange, foregroundColor: Colors.white), body: Center(child: Text(_hataMesaji)));

    return Scaffold(
      appBar: AppBar(title: const Text('Konumu Seç ve Yıkamacı Çağır'), backgroundColor: Colors.orange, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('kullanicilar').where('rol', isEqualTo: 'calisan').snapshots(),
        builder: (context, snapshot) {
          Set<Marker> markers = {};
          
          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              var data = doc.data() as Map<String, dynamic>;
              if (data.containsKey('enlem') && data.containsKey('boylam')) {
                double lat = (data['enlem'] as num).toDouble();
                double lng = (data['boylam'] as num).toDouble();
                String isim = data['adSoyad'] ?? 'Yıkamacı Usta';
                if (lat != 0.0 && lng != 0.0) {
                  markers.add(Marker(markerId: MarkerId(doc.id), position: LatLng(lat, lng), infoWindow: InfoWindow(title: isim, snippet: 'Müsait'), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)));
                }
              }
            }
          }

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: _suAnkiKonum!, zoom: 15),
                markers: markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                },
                onCameraMove: (position) {
                  _suAnkiKonum = position.target;
                },
              ),
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 35),
                  child: Icon(Icons.location_pin, size: 45, color: Colors.red),
                ),
              ),
              Positioned(
                bottom: 30, left: 20, right: 20,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _ilanGonder,
                  child: const Text('Bu Konuma Yıkamacı Çağır 🚗✨', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

class CanliTakipEkrani extends StatelessWidget {
  final String calisanUid;
  const CanliTakipEkrani({super.key, required this.calisanUid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yıkamacı Canlı Takip'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('kullanicilar').doc(calisanUid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return const Center(child: Text('Çalışan konumu bulunamadı.'));

          var data = snapshot.data!.data() as Map<String, dynamic>;
          double lat = (data['enlem'] ?? 0.0).toDouble();
          double lng = (data['boylam'] ?? 0.0).toDouble();

          if (lat == 0.0 || lng == 0.0) {
            return const Center(child: Text('Çalışan henüz konum paylaşmıyor...', style: TextStyle(fontSize: 16, color: Colors.grey)));
          }

          LatLng calisanKonum = LatLng(lat, lng);

          return GoogleMap(
            initialCameraPosition: CameraPosition(target: calisanKonum, zoom: 16),
            myLocationEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            markers: {
              Marker(
                markerId: const MarkerId('yikamaci_canli'),
                position: calisanKonum,
                infoWindow: const InfoWindow(title: 'Yıkamacı Usta Yolda 🚀'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              )
            },
          );
        },
      ),
    );
  }
}

class IlanKartWidget extends StatelessWidget {
  final String ilanId;
  final Map<String, dynamic> data;
  final bool isGecmis;

  const IlanKartWidget({super.key, required this.ilanId, required this.data, required this.isGecmis});

  String _zamanFormatla(String raw) {
    try {
      DateTime dt = DateTime.parse(raw);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    String tur = data['isAninda'] == true ? 'Anında Yıkama' : 'Randevulu Yıkama';
    String zaman = data['isAninda'] == true ? _zamanFormatla(data['olusturma']) : '${data['tarih']} - ${data['saat']}';
    String durumText = data['durum'].toString().toUpperCase();
    
    Color durumRenk;
    if (isGecmis) {
      durumRenk = Colors.green;
    } else if (data['durum'] == 'onaylandi') {
      durumRenk = Colors.blueAccent;
    } else {
      durumRenk = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${data['aracTipi']} - ${data['plaka']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Icon(data['isAninda'] == true ? Icons.bolt : Icons.calendar_month, color: Colors.grey.shade600, size: 24),
              ],
            ),
            const Divider(height: 24),
            Row(children: [const Icon(Icons.info_outline, size: 18, color: Colors.grey), const SizedBox(width: 8), Text('Tür: $tur', style: const TextStyle(fontSize: 15))]),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.access_time, size: 18, color: Colors.grey), const SizedBox(width: 8), Text('Zaman: $zaman', style: const TextStyle(fontSize: 15))]),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Durum: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: durumRenk.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(durumText, style: TextStyle(color: durumRenk, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
            if (data.containsKey('calisanUid') && data['calisanUid'] != null) ...[
              const Divider(height: 24),
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('kullanicilar').doc(data['calisanUid']).get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Yıkamacı: Yükleniyor...', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
                  }
                  if (snapshot.hasData && snapshot.data!.exists) {
                    var calisanData = snapshot.data!.data() as Map<String, dynamic>;
                    String calisanAd = calisanData['adSoyad'] ?? 'Bilinmiyor';
                    String calisanTel = calisanData['telefon'] ?? '';
                    String? profilFoto = calisanData['profilFoto'];

                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: (profilFoto != null && profilFoto.isNotEmpty) ? NetworkImage(profilFoto) : null,
                                child: (profilFoto == null || profilFoto.isEmpty) ? const Icon(Icons.person, size: 30, color: Colors.grey) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Yıkamacı: $calisanAd', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text('Tel: $calisanTel', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                                    const SizedBox(height: 2),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isGecmis && data['durum'] == 'onaylandi') ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                              icon: const Icon(Icons.map, size: 18),
                              label: const Text('Haritada Canlı Takip Et 📍'),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CanliTakipEkrani(calisanUid: data['calisanUid']),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.chat, size: 18),
                                  label: const Text('Mesajlaş'),
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => SohbetEkrani(ilanId: ilanId, karsiTarafAd: calisanAd, karsiTarafTel: calisanTel)));
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.phone, size: 18),
                                  label: const Text('Ara'),
                                  onPressed: () async {
                                    final Uri launchUri = Uri(scheme: 'tel', path: calisanTel);
                                    if (await canLaunchUrl(launchUri)) {
                                      await launchUrl(launchUri);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ]
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              )
            ]
          ],
        ),
      ),
    );
  }
}

class AktifIlanlarEkrani extends StatelessWidget {
  const AktifIlanlarEkrani({super.key});
  
  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Aktif İlanlarım'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('ilanlar').where('musteriUid', isEqualTo: user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var docs = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data['durum'] == 'bekliyor' || data['durum'] == 'onaylandi';
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text('Şu anda aktif bir ilanınız bulunmuyor.', style: TextStyle(fontSize: 16, color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return IlanKartWidget(ilanId: docs[index].id, data: docs[index].data() as Map<String, dynamic>, isGecmis: false);
            },
          );
        },
      ),
    );
  }
}

class GecmisIlanlarEkrani extends StatelessWidget {
  const GecmisIlanlarEkrani({super.key});
  
  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Geçmiş İlanlarım'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('ilanlar').where('musteriUid', isEqualTo: user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          var docs = snapshot.data!.docs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            return data['durum'] == 'tamamlandi';
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text('Henüz tamamlanmış geçmiş bir ilanınız yok.', style: TextStyle(fontSize: 16, color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return IlanKartWidget(ilanId: docs[index].id, data: docs[index].data() as Map<String, dynamic>, isGecmis: true);
            },
          );
        },
      ),
    );
  }
}

class SohbetEkrani extends StatefulWidget {
  final String ilanId;
  final String karsiTarafAd;
  final String karsiTarafTel;
  const SohbetEkrani({super.key, required this.ilanId, required this.karsiTarafAd, required this.karsiTarafTel});

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani> {
  final TextEditingController _mesajController = TextEditingController();

  Future<void> _mesajGonder() async {
    if (_mesajController.text.trim().isEmpty) return;
    String text = _mesajController.text.trim();
    _mesajController.clear();

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('mesajlar').add({
      'ilanId': widget.ilanId,
      'gonderenUid': user.uid,
      'mesaj': text,
      'zaman': DateTime.now().toString(),
    });
  }

  Future<void> _telefonAra() async {
    final Uri launchUri = Uri(scheme: 'tel', path: widget.karsiTarafTel);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    String myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.karsiTarafAd),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: _telefonAra,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('mesajlar')
                  .where('ilanId', isEqualTo: widget.ilanId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snapshot.data!.docs;

                docs.sort((a, b) {
                  var aData = a.data() as Map<String, dynamic>;
                  var bData = b.data() as Map<String, dynamic>;
                  var aTime = aData['zaman'] ?? '';
                  var bTime = bData['zaman'] ?? '';
                  return bTime.compareTo(aTime);
                });

                if (docs.isEmpty) return const Center(child: Text('Henüz mesaj yok. Sohbeti başlatın!'));

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    bool benMiyim = data['gonderenUid'] == myUid;

                    return Align(
                      alignment: benMiyim ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: benMiyim ? Colors.blue.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(data['mesaj'] ?? '', style: const TextStyle(fontSize: 15)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mesajController,
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yazın...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: _mesajGonder,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}