import 'engine.dart';

// Preparation metadata only. No selection authorizes fiscal emission.
const fiscalChoices = <String, Map<String, String>>{
  'legalForm': {
    'unknown': 'Pendiente de confirmar',
    'sole_trader': 'Autónomo / persona física',
    'company': 'Sociedad',
    'attribution': 'Entidad en atribución de rentas',
    'other': 'Otra forma jurídica, por revisar',
  },
  'territory': {
    'unknown': 'Pendiente de confirmar',
    'common': 'Territorio común · Península / Baleares',
    'canary': 'Canarias',
    'ceuta': 'Ceuta',
    'melilla': 'Melilla',
    'navarra': 'Navarra',
    'alava': 'Álava',
    'bizkaia': 'Bizkaia',
    'gipuzkoa': 'Gipuzkoa',
  },
  'sii': {
    'unknown': 'Pendiente de confirmar',
    'yes': 'Sí, utiliza SII',
    'no': 'No utiliza SII',
  },
  'clients': {
    'unknown': 'Pendiente de confirmar',
    'individuals': 'Particulares',
    'business': 'Empresas y profesionales',
    'public': 'Administraciones públicas',
    'mixed': 'Varios de los anteriores',
  },
  'turnover': {
    'unknown': 'Pendiente de confirmar',
    'under_8m': 'Hasta 8 millones de euros inclusive',
    'over_8m': 'Más de 8 millones de euros',
  },
  'taxSystem': {
    'unknown': 'Pendiente de confirmar',
    'iva': 'IVA',
    'igic': 'IGIC',
    'ipsi': 'IPSI',
    'mixed': 'Varios impuestos, por revisar',
    'other': 'Otro régimen, por revisar',
  },
};

const fiscalFieldLabels = {
  'legalForm': 'Tipo de titular',
  'territory': 'Territorio fiscal del taller',
  'sii': 'Libros mediante SII',
  'clients': 'Tipos de clientes',
  'turnover': 'Volumen de operaciones del año anterior',
  'taxSystem': 'Impuesto habitual, pendiente de revisión fiscal',
};

Map<String, dynamic> initialFiscalProfile() => {
  'country': 'ES',
  for (final field in fiscalChoices.keys) field: 'unknown',
  'profileVersion': 1,
  'emissionEnabled': false,
};

Map<String, dynamic> validateFiscalProfile(dynamic input) {
  if (input is! Map ||
      input['country'] != 'ES' ||
      input.keys.any(
        (key) => !{
          ...fiscalChoices.keys,
          'country',
          'profileVersion',
          'emissionEnabled',
        }.contains(key),
      ) ||
      (input.containsKey('profileVersion') && input['profileVersion'] != 1) ||
      (input.containsKey('emissionEnabled') &&
          input['emissionEnabled'] != false)) {
    throw const RuleException('Perfil fiscal de preparación inválido');
  }
  for (final field in fiscalChoices.keys) {
    if (input[field] is! String ||
        !fiscalChoices[field]!.containsKey(input[field])) {
      throw RuleException('${fiscalFieldLabels[field]}: revisa la opción');
    }
  }
  return {
    'country': 'ES',
    for (final field in fiscalChoices.keys) field: input[field],
    'profileVersion': 1,
    'emissionEnabled': false,
  };
}
