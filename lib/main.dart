import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final prefs = await SharedPreferences.getInstance();
  bool beniHatirla = prefs.getBool('beni_hatirla') ?? false;
  User? currentUser = FirebaseAuth.instance.currentUser;

  Widget baslangicEkrani = (beniHatirla && currentUser != null)
      ? const AnaSayfaYoneticisi()
      : const KarsilamaEkrani();

  runApp(ArabaYikamaApp(baslangicEkrani: baslangicEkrani));
}

// Ortak Çıkış Yap Fonksiyonu
Future<void> cikisYap(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('beni_hatirla', false);
  await prefs.remove('kayitli_email');

  if (context.mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const GirisEkrani()),
    );
  }
}

// Telefon Araması Yardımcı Fonksiyonu
Future<void>telefonlaAra(BuildContext context, String hedefUid) async {
  if (hedefUid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Atanmış kullanıcı bilgisi bulunamadı.'), backgroundColor: Colors.orange),
    );
    return;
  }

  try {
    DocumentSnapshot doc = await FirebaseFirestore.instance.collection('kullanicilar').doc(hedefUid).get();
    if (doc.exists) {
      var data = doc.data() as Map<String, dynamic>?;
      String telefon = data?['telefon'] ?? '';
      if (telefon.isNotEmpty) {
        final Uri launchUri = Uri(scheme: 'tel', path: telefon);
        if (await canLaunchUrl(launchUri)) {
          await launchUrl(launchUri);
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Arama başlatılamadı.'), backgroundColor: Colors.red),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullanıcının telefon numarası kayıtlı değil.'), backgroundColor: Colors.orange),
          );
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

class ArabaYikamaApp extends StatelessWidget {
  final Widget baslangicEkrani;
  const ArabaYikamaApp({super.key, required this.baslangicEkrani});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Araba Yıkama Pazaryeri',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
      ],
      locale: const Locale('tr', 'TR'),
      home: baslangicEkrani,
    );
  }
}

// ==========================================
// 1. ŞIK KARŞILAMA EKRANI
// ==========================================
class KarsilamaEkrani extends StatelessWidget {
  const KarsilamaEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueAccent, Colors.blue.shade800],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Icon(
                  Icons.local_car_wash,
                  size: 100,
                  color: Colors.white,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Kapıda Araba Yıkama',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Aracınızı istediğiniz saatte, dilediğiniz konumda profesyonelce yıkanmasını sağlayın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const GirisEkrani()),
                    );
                  },
                  child: const Text(
                    'Hadi Başlayalım',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. GİRİŞ YAP / KAYIT OL EKRANI
// ==========================================
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  bool kayitOlMode = false;
  bool beniHatirla = false;
  final TextEditingController epostaController = TextEditingController();
  final TextEditingController sifreController = TextEditingController();
  bool yukleniyor = false;

  @override
  void initState() {
    super.initState();
    _kayitliTercihleriYukle();
  }

  Future<void> _kayitliTercihleriYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      beniHatirla = prefs.getBool('beni_hatirla') ?? false;
      if (beniHatirla) {
        epostaController.text = prefs.getString('kayitli_email') ?? '';
      }
    });
  }

  Future<void> _sifreSifirla() async {
    final email = epostaController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce şifresini yenilemek istediğiniz e-posta adresini yukarıdaki kutuya yazın!'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifre sıfırlama bağlantısı e-posta adresinize gönderildi. Lütfen e-postanızı kontrol edin.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bir hata oluştu. E-posta adresinizi doğru yazdığınızdan emin olun.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _islemYap() async {
    final email = epostaController.text.trim();
    final password = sifreController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen e-posta ve şifreyi doldurun!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() { yukleniyor = true; });

    try {
      if (kayitOlMode) {
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfilTamamlamaEkrani(user: userCredential.user!)),
          );
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('beni_hatirla', beniHatirla);
        if (beniHatirla) {
          await prefs.setString('kayitli_email', email);
        } else {
          await prefs.remove('kayitli_email');
        }
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AnaSayfaYoneticisi()),
          );
        }
      }
    } catch (e) {
      String gorunurHata = 'Bir hata oluştu, lütfen tekrar deneyin.';
      
      if (e is FirebaseAuthException) {
        if (e.code == 'user-not-found' || 
            e.code == 'wrong-password' || 
            e.code == 'invalid-credential' || 
            e.code == 'invalid-email' ||
            e.code == 'channel-error') {
          gorunurHata = 'E-mail veya şifreniz hatalı!';
        } else if (e.code == 'email-already-in-use') {
          gorunurHata = 'Bu e-posta adresi zaten kullanımda.';
        } else if (e.code == 'weak-password') {
          gorunurHata = 'Şifreniz çok zayıf, en az 6 karakter olmalıdır.';
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(gorunurHata), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) { setState(() { yukleniyor = false; }); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(kayitOlMode ? 'Yeni Hesap Oluştur' : 'Giriş Yap'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_person, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 24),
                TextField(
                  controller: epostaController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-Posta Adresi',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: sifreController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: beniHatirla,
                      activeColor: Colors.blueAccent,
                      onChanged: (yeniDeger) {
                        setState(() {
                          beniHatirla = yeniDeger ?? false;
                        });
                      },
                    ),
                    const Text(
                      'Beni Hatırla',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                yukleniyor
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _islemYap,
                        child: Text(
                          kayitOlMode ? 'Kayıt Ol' : 'Giriş Yap',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      kayitOlMode = !kayitOlMode;
                    });
                  },
                  child: Text(
                    kayitOlMode ? 'Zaten hesabınız var mı? Giriş yapın' : 'Hesabınız yok mu? Kayıt olun',
                    style: const TextStyle(color: Colors.blueAccent),
                  ),
                ),
                if (!kayitOlMode)
                  TextButton(
                    onPressed: _sifreSifirla,
                    child: const Text(
                      'Şifremi Unuttum',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. PROFİL TAMAMLAMA EKRANI
// ==========================================
class ProfilTamamlamaEkrani extends StatefulWidget {
  final User user;
  const ProfilTamamlamaEkrani({super.key, required this.user});

  @override
  State<ProfilTamamlamaEkrani> createState() => _ProfilTamamlamaEkraniState();
}

class _ProfilTamamlamaEkraniState extends State<ProfilTamamlamaEkrani> {
  final TextEditingController adSoyadController = TextEditingController();
  final TextEditingController telefonController = TextEditingController();
  File? secilenResimDosyasi;
  bool yukleniyor = false;

  Future<void> _galeridenSec() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (pickedFile != null) {
      setState(() {
        secilenResimDosyasi = File(pickedFile.path);
      });
    }
  }

  Future<void> _profiliKaydet() async {
    final adSoyad = adSoyadController.text.trim();
    final telefon = telefonController.text.trim();

    if (adSoyad.isEmpty || telefon.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen ad soyad ve telefon numaranızı girin!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() { yukleniyor = true; });

    try {
      String fotoUrl = '';

      if (secilenResimDosyasi != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('profil_fotograflari')
              .child('${widget.user.uid}.jpg');

          await storageRef.putFile(secilenResimDosyasi!);
          fotoUrl = await storageRef.getDownloadURL();
        } catch (storageError) {
          print('Storage atlandı: $storageError');
        }
      }

      await FirebaseFirestore.instance.collection('kullanicilar').doc(widget.user.uid).set({
        'uid': widget.user.uid,
        'email': widget.user.email,
        'adSoyad': adSoyad,
        'telefon': telefon,
        'profilFotoUrl': fotoUrl,
        'kayitTarihi': DateTime.now().toString(),
      });

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kayıt başarılı! Lütfen e-posta ve şifrenizle giriş yapın.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const GirisEkrani()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() { yukleniyor = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilinizi Tamamlayın'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: secilenResimDosyasi != null ? FileImage(secilenResimDosyasi!) : null,
                        child: secilenResimDosyasi == null
                            ? const Icon(Icons.person, size: 60, color: Colors.white)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          radius: 18,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            onPressed: _galeridenSec,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: adSoyadController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: telefonController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon Numarası',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                    hintText: '05XXXXXXXXX',
                  ),
                ),
                const SizedBox(height: 24),
                yukleniyor
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _profiliKaydet,
                        child: const Text(
                          'Profili Tamamla ve Giriş Ekranına Dön',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 4. ANA SAYFA YÖNETİCİSİ
// ==========================================
class AnaSayfaYoneticisi extends StatefulWidget {
  const AnaSayfaYoneticisi({super.key});

  @override
  State<AnaSayfaYoneticisi> createState() => _AnaSayfaYoneticisiState();
}

class _AnaSayfaYoneticisiState extends State<AnaSayfaYoneticisi> {
  int _secilenIndex = 0;

  final List<Widget> _sayfalar = [
    const IlanOlusturEkrani(),
    const IlanlarimEkrani(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _sayfalar[_secilenIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _secilenIndex,
        selectedItemColor: Colors.blueAccent,
        onTap: (index) {
          setState(() {
            _secilenIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'İlanlarım',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. ANA EKRAN (HİZMET SEÇİMİ)
// ==========================================
class IlanOlusturEkrani extends StatelessWidget {
  const IlanOlusturEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hizmetlerimiz', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: () => cikisYap(context),
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade100,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ne yaptırmak istersiniz?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2, 
                crossAxisSpacing: 16, 
                mainAxisSpacing: 16, 
                children: [
                  _buildKareButon(
                    context,
                    baslik: 'Kapıda Araba\nYıkama',
                    icon: Icons.local_car_wash,
                    renk: Colors.blueAccent,
                    aktif: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AracBilgiGirisEkrani()),
                      );
                    },
                  ),
                  _buildKareButon(
                    context,
                    baslik: 'Oto Kuaför\n(Yakında)',
                    icon: Icons.cleaning_services,
                    renk: Colors.grey.shade500,
                    aktif: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bu hizmet çok yakında eklenecektir!')),
                      );
                    },
                  ),
                  _buildKareButon(
                    context,
                    baslik: 'Lastik Değişimi\n(Yakında)',
                    icon: Icons.tire_repair,
                    renk: Colors.grey.shade500,
                    aktif: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bu hizmet çok yakında eklenecektir!')),
                      );
                    },
                  ),
                  _buildKareButon(
                    context,
                    baslik: 'Periyodik Bakım\n(Yakında)',
                    icon: Icons.car_repair,
                    renk: Colors.grey.shade500,
                    aktif: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bu hizmet çok yakında eklenecektir!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKareButon(
      BuildContext context, {
      required String baslik,
      required IconData icon,
      required Color renk,
      required bool aktif,
      required VoidCallback onTap,
    }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: renk.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: renk),
            ),
            const SizedBox(height: 12),
            Text(
              baslik,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: aktif ? Colors.black87 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 6. ADIM 1: ARAÇ BİLGİLERİ, TAKVİM VE SAAT
// ==========================================
class AracBilgiGirisEkrani extends StatefulWidget {
  const AracBilgiGirisEkrani({super.key});

  @override
  State<AracBilgiGirisEkrani> createState() => _AracBilgiGirisEkraniState();
}

class _AracBilgiGirisEkraniState extends State<AracBilgiGirisEkrani> {
  String secilenAracTipi = 'Sedan';
  final TextEditingController plakaKontrolcusu = TextEditingController();
  DateTime secilenTarih = DateTime.now();
  int secilenSaatDegeri = 12;
  int secilenDakikaDegeri = 00;

  Future<void> _tarihSec(BuildContext context) async {
    final DateTime? secilen = await showDatePicker(
      context: context,
      initialDate: secilenTarih,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      helpText: 'Yıkama Günü Seçin',
      confirmText: 'Seç',
      cancelText: 'İptal',
    );

    if (secilen != null) {
      setState(() {
        secilenTarih = secilen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String formatliTarih = '${secilenTarih.day.toString().padLeft(2, '0')}.${secilenTarih.month.toString().padLeft(2, '0')}.${secilenTarih.year}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Araç ve Zaman Bilgisi'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Araç Tipini Seçin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: secilenAracTipi,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: ['Sedan', 'Hatchback', 'SUV', 'Minivan', 'Ticari'].map((String tip) {
                return DropdownMenuItem<String>(
                  value: tip,
                  child: Text(tip),
                );
              }).toList(),
              onChanged: (yeniDeger) {
                setState(() {
                  secilenAracTipi = yeniDeger!;
                });
              },
            ),
            const SizedBox(height: 20),
            const Text('Araç Plakasını Girin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            TextField(
              controller: plakaKontrolcusu,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Örn: 34ABC123',
                prefixIcon: Icon(Icons.badge, color: Colors.blueAccent),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Yıkatmak İstediğiniz Günü Seçin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _tarihSec(context),
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today, color: Colors.blueAccent),
                ),
                child: Text(
                  formatliTarih,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Yıkatmak İstediğiniz Saati Seçin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      const Text('SAAT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.blueAccent),
                            onPressed: () {
                              setState(() {
                                if (secilenSaatDegeri > 0) secilenSaatDegeri--;
                                else secilenSaatDegeri = 23;
                              });
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.blueAccent),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              secilenSaatDegeri.toString().padLeft(2, '0'),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                            onPressed: () {
                              setState(() {
                                if (secilenSaatDegeri < 23) secilenSaatDegeri++;
                                else secilenSaatDegeri = 0;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ),
                  Column(
                    children: [
                      const Text('DAKİKA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.blueAccent),
                            onPressed: () {
                              setState(() {
                                if (secilenDakikaDegeri >= 5) secilenDakikaDegeri -= 5;
                                else secilenDakikaDegeri = 55;
                              });
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.blueAccent),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              secilenDakikaDegeri.toString().padLeft(2, '0'),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                            onPressed: () {
                              setState(() {
                                if (secilenDakikaDegeri <= 50) secilenDakikaDegeri += 5;
                                else secilenDakikaDegeri = 0;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                String plaka = plakaKontrolcusu.text.trim();
                if (plaka.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen araç plakasını boş bırakmayınız!'), backgroundColor: Colors.red),
                  );
                  return;
                }

                String formatliSaat = '${secilenSaatDegeri.toString().padLeft(2, '0')}:${secilenDakikaDegeri.toString().padLeft(2, '0')}';

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HaritaKonumSecimEkrani(
                      aracTipi: secilenAracTipi,
                      plaka: plaka,
                      secilenTarih: formatliTarih,
                      saat: formatliSaat,
                    ),
                  ),
                );
              },
              child: const Text('Devam Et', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 7. ADIM 2: HARİTADAN KONUM SEÇME
// ==========================================
class HaritaKonumSecimEkrani extends StatefulWidget {
  final String aracTipi;
  final String plaka;
  final String secilenTarih;
  final String saat;

  const HaritaKonumSecimEkrani({
    super.key,
    required this.aracTipi,
    required this.plaka,
    required this.secilenTarih,
    required this.saat,
  });

  @override
  State<HaritaKonumSecimEkrani> createState() => _HaritaKonumSecimEkraniState();
}

class _HaritaKonumSecimEkraniState extends State<HaritaKonumSecimEkrani> {
  GoogleMapController? _controller;
  LatLng _merkezKonum = const LatLng(41.0082, 28.9784);
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _kullaniciKonumunuAl();
  }

  Future<void> _kullaniciKonumunuAl() async {
    bool servisAcik;
    LocationPermission izin;

    try {
      servisAcik = await Geolocator.isLocationServiceEnabled();
      if (!servisAcik) {
        setState(() { _yukleniyor = false; });
        return;
      }

      izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
        if (izin == LocationPermission.denied) {
          setState(() { _yukleniyor = false; });
          return;
        }
      }

      if (izin == LocationPermission.deniedForever) {
        setState(() { _yukleniyor = false; });
        return;
      }

      Position konum = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _merkezKonum = LatLng(konum.latitude, konum.longitude);
        _yukleniyor = false;
      });

      if (_controller != null) {
        _controller!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _merkezKonum, zoom: 16.0),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _yukleniyor = false;
      });
    }
  }

  Future<void> _adresDetaylariniAl() async {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => const Center(child: CircularProgressIndicator())
    );

    String varsayilanMahalle = '';
    String varsayilanSokak = '';
    String varsayilanSehir = '';

    try {
      final geocoding = Geocoding();
      List<Placemark> placemarks = await geocoding.placemarkFromCoordinates(
        _merkezKonum.latitude,
        _merkezKonum.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark yer = placemarks.first;
        varsayilanMahalle = yer.subLocality ?? ''; 
        varsayilanSokak = yer.thoroughfare ?? yer.street ?? ''; 
        varsayilanSehir = yer.administrativeArea ?? '';
      }
    } catch (e) {
      // Hata durumu
    }

    if (!mounted) return;
    Navigator.pop(context);

    _adresFormunuGoster(varsayilanMahalle, varsayilanSokak, varsayilanSehir);
  }

  void _adresFormunuGoster(String mahalle, String sokak, String sehir) {
    final mahalleCtrl = TextEditingController(text: mahalle);
    final sokakCtrl = TextEditingController(text: sokak);
    final binaNoCtrl = TextEditingController();
    final kapiNoCtrl = TextEditingController();
    final tarifCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Adres Detaylarını Girin',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: mahalleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mahalle',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: sokakCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Sokak / Cadde',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.signpost),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: binaNoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bina Adı / No',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.home),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: kapiNoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Kat / Daire',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.door_front_door),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tarifCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Adres Tarifi (İsteğe Bağlı)',
                    border: OutlineInputBorder(),
                    hintText: 'Örn: Parkın karşısındaki sarı bina',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _finalIlanKaydet(
                    mahalleCtrl.text,
                    sokakCtrl.text,
                    binaNoCtrl.text,
                    kapiNoCtrl.text,
                    tarifCtrl.text,
                    sehir,
                  ),
                  child: const Text(
                    'İlanı Tamamla ve Gönder',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _finalIlanKaydet(String mahalle, String sokak, String bina, String kapi, String tarif, String sehir) async {
    if (mahalle.isEmpty || sokak.isEmpty || bina.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen Mahalle, Sokak ve Bina No alanlarını doldurun!'), backgroundColor: Colors.red),
      );
      return;
    }

    String tamAdres = 'Mahalle: $mahalle, Sok/Cad: $sokak, Bina: $bina';
    if (kapi.isNotEmpty) tamAdres += ', Daire: $kapi';
    if (sehir.isNotEmpty) tamAdres += ', $sehir';
    if (tarif.isNotEmpty) tamAdres += '\nTarif: $tarif';

    User? currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser != null) {
      await FirebaseFirestore.instance.collection('ilanlar').add({
        'musteriUid': currentUser.uid,
        'aracTipi': widget.aracTipi,
        'plaka': widget.plaka.toUpperCase(),
        'adres': tamAdres,
        'enlem': _merkezKonum.latitude,
        'boylam': _merkezKonum.longitude,
        'tarihGun': widget.secilenTarih,
        'saat': widget.saat,
        'olusturma': DateTime.now().toString().substring(0, 16),
        'durum': 'bekliyor',
      });
    }

    if (!mounted) return;
    
    Navigator.pop(context);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AnaSayfaYoneticisi()),
      (route) => false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İlan başarıyla oluşturuldu!'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aracınızı yıkatmak istediğiniz konumu seçin', style: TextStyle(fontSize: 15)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _yukleniyor
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Konumunuz alınıyor, lütfen bekleyin...', style: TextStyle(fontSize: 15)),
                ],
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _merkezKonum,
                    zoom: 14.0,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  onMapCreated: (controller) {
                    _controller = controller;
                  },
                  onCameraMove: (kamerePozisyonu) {
                    _merkezKonum = kamerePozisyonu.target;
                  },
                ),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(
                      Icons.location_pin,
                      size: 50,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _adresDetaylariniAl,
                    child: const Text(
                      'Konumu Onayla',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ==========================================
// 8. İLANLARIM EKRANI
// ==========================================
class IlanlarimEkrani extends StatefulWidget {
  const IlanlarimEkrani({super.key});

  @override
  State<IlanlarimEkrani> createState() => _IlanlarimEkraniState();
}

class _IlanlarimEkraniState extends State<IlanlarimEkrani> {
  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktif İlanlarım'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: () => cikisYap(context),
          ),
        ],
      ),
      body: currentUser == null
          ? const Center(child: Text('Lütfen giriş yapın.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ilanlar')
                  .where('musteriUid', isEqualTo: currentUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Henüz aktif bir ilanınız yok.\nAna sayfadan "Arabamı Yıkatmak İstiyorum" butonuna basarak yeni ilan ekleyebilirsiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                var ilanlar = snapshot.data!.docs;
                ilanlar.sort((a, b) => b['olusturma'].toString().compareTo(a['olusturma'].toString()));

                return ListView.builder(
                  itemCount: ilanlar.length,
                  itemBuilder: (context, index) {
                    var ilan = ilanlar[index];
                    var docId = ilan.id;
                    Map<String, dynamic> ilanData = ilan.data() as Map<String, dynamic>;

                    String durum = ilanData['durum'] ?? 'bekliyor';
                    Color durumRengi;
                    String durumMetni;

                    if (durum == 'bekliyor') {
                      durumRengi = Colors.orange;
                      durumMetni = 'Çalışan Bekleniyor...';
                    } else if (durum == 'onaylandi') {
                      durumRengi = Colors.green;
                      durumMetni = 'Onaylandı! Araç Yıkanacak';
                    } else {
                      durumRengi = Colors.blue;
                      durumMetni = 'Aracınızın temizliği yapılmıştır! 🚗✨ İyi günler dileriz.';
                    }
                    
                    String calisanUid = ilanData.containsKey('calisanUid') ? ilanData['calisanUid'] : ''; 

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: Colors.blueAccent,
                                child: Icon(Icons.directions_car, color: Colors.white),
                              ),
                              title: Text(
                                'Araç: ${ilanData['aracTipi']} (${ilanData['plaka']})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text('Adres: ${ilanData['adres']}'),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today, size: 14, color: Colors.blueAccent),
                                      const SizedBox(width: 4),
                                      Text('Yıkama: ${ilanData['tarihGun']} - ${ilanData['saat']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: durumRengi.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: durumRengi, width: 1),
                                    ),
                                    child: Text(
                                      durumMetni,
                                      style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'İlanı Sil',
                                onPressed: () async {
                                  await FirebaseFirestore.instance.collection('ilanlar').doc(docId).delete();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('İlan silindi.'), backgroundColor: Colors.orange, duration: Duration(seconds: 1)),
                                    );
                                  }
                                },
                              ),
                            ),
                            if (durum == 'onaylandi') ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(Icons.chat, size: 18),
                                      label: const Text('Mesaj', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => SohbetEkrani(
                                              ilanId: docId,
                                              baslikBilgisi: ilanData['plaka'],
                                              calisanUid: calisanUid,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(Icons.phone, size: 18),
                                      label: const Text('Ara', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () => telefonlaAra(context, calisanUid),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
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
// 9. ANLIK SOHBET EKRANI
// ==========================================
class SohbetEkrani extends StatefulWidget {
  final String ilanId;
  final String baslikBilgisi;
  final String calisanUid;

  const SohbetEkrani({super.key, required this.ilanId, required this.baslikBilgisi, required this.calisanUid});

  @override
  State<SohbetEkrani> createState() => _SohbetEkraniState();
}

class _SohbetEkraniState extends State<SohbetEkrani> {
  final TextEditingController _mesajController = TextEditingController();

  Future<void> _mesajGonder() async {
    final text = _mesajController.text.trim();
    if (text.isEmpty) return;

    _mesajController.clear();
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      await FirebaseFirestore.instance
          .collection('ilanlar')
          .doc(widget.ilanId)
          .collection('mesajlar')
          .add({
        'gonderenUid': currentUser.uid,
        'mesaj': text,
        'zaman': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sohbet: ${widget.baslikBilgisi}'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: 'Çalışanı Ara',
            onPressed: () => telefonlaAra(context, widget.calisanUid),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('ilanlar')
                  .doc(widget.ilanId)
                  .collection('mesajlar')
                  .orderBy('zaman', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Henüz mesaj yok. İlk mesajı siz yazın!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                var mesajlar = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: mesajlar.length,
                  itemBuilder: (context, index) {
                    var mesajData = mesajlar[index];
                    bool benimMesajim = mesajData['gonderenUid'] == currentUser?.uid;

                    return Align(
                      alignment: benimMesajim ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: benimMesajim ? Colors.blueAccent : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          mesajData['mesaj'] ?? '',
                          style: TextStyle(
                            color: benimMesajim ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mesajController,
                    decoration: const InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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