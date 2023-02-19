# FaceAccess Client

Esta es la implementación de la aplicación móvil del cliente del sistema FaceAccess. 

[![Watch the video](https://img.youtube.com/vi/7-49Uec5LTM/0.jpg)](https://youtu.be/7-49Uec5LTM)


## *Funcionamiento*

Este proyecto corresponde con el backend del servicio para el funcionamiento del sistema de control de acceso **FaceAccess**.

En ella se controlarán todas las comunicaciones entre base de datos y cliente. Para dicha comunicación se empleará el protocolo **MQTT**, el cual permite comunicar de forma rápida y eficiente dispositivos de IoT, para llevar a cabo esta comunicación, se emplearán diferentes tópicos gestionados por un broker llamado **Mosquitto**. 

Para ello se han seguido dos arquitecturas, la primera para la comunicación entre servicio y aplicación del cliente (**FaceAccess Client**), y la comunicación entre servicio y aplicación del empleado (**FaceAccess Employee**).

## *Imágenes de la aplicación móvil*

<figure>
  <img
  src="./images/image1.jpeg"
  alt="Inicio de la aplicación.">
</figure>

<figure>
  <img
  src="./images/image3.jpeg"
  alt="Lector QR.">
</figure>

<figure>
  <img
  src="./images/image2.jpeg"
  alt="Reconocimiento facial.">
</figure>

