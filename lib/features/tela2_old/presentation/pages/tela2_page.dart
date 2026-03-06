import 'package:flutter/material.dart';
import '../../../../core/widgets/app_drawer.dart';

class Tela2Page extends StatefulWidget {
  const Tela2Page({super.key});

  @override
  State<Tela2Page> createState() => _Tela2PageState();
}

class _Tela2PageState extends State<Tela2Page> {
  double _rotation = 0.0;
  double _scale = 1.0;
  Offset _position = const Offset(0, 0);
  bool _isPressed = false;
  Color _cardColor = Colors.white.withOpacity(0.1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interatividade Avançada'),
      ),
      drawer: const AppDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Widgets Interativos',
              style: TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),

            // Card interativo com gestos
            GestureDetector(
              onTap: () {
                setState(() {
                  _cardColor = _cardColor == Colors.white.withOpacity(0.1)
                      ? Colors.white.withOpacity(0.3)
                      : Colors.white.withOpacity(0.1);
                });
              },
              onLongPress: () {
                setState(() {
                  _isPressed = !_isPressed;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white,
                    width: _isPressed ? 3 : 1,
                  ),
                  boxShadow: _isPressed
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isPressed ? Icons.favorite : Icons.favorite_border,
                        color: Colors.white,
                        size: 50,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isPressed ? 'Pressionado!' : 'Toque aqui',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Card Interativo (Toque e Segure)',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 40),

            // Widget rotacionável
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _rotation += details.delta.dx * 0.01;
                });
              },
              child: Transform.rotate(
                angle: _rotation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Rotacione arrastando',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 40),

            // Widget escalável
            GestureDetector(
              onScaleUpdate: (details) {
                setState(() {
                  _scale = details.scale.clamp(0.5, 2.0);
                });
              },
              onScaleEnd: (details) {
                setState(() {
                  _scale = 1.0;
                });
              },
              child: Transform.scale(
                scale: _scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.zoom_in,
                    color: Colors.black,
                    size: 50,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Pinça para escalar',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 40),

            // Widget arrastável
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _position += details.delta;
                });
              },
              child: Transform.translate(
                offset: _position,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.8),
                        Colors.white.withOpacity(0.4),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.drag_handle,
                    color: Colors.black,
                    size: 40,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Arraste para mover',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 40),

            // Lista interativa com efeito parallax
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                itemBuilder: (context, index) {
                  return Container(
                    width: 150,
                    margin: const EdgeInsets.only(right: 15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.star,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Item ${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Lista Horizontal Interativa',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                setState(() {
                  _rotation = 0.0;
                  _scale = 1.0;
                  _position = const Offset(0, 0);
                  _isPressed = false;
                  _cardColor = Colors.white.withOpacity(0.1);
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
              ),
              child: const Text('Resetar'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
              ),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}

