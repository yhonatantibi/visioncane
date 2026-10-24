import unittest
from build_indoor_model import validate_names

class ModelContractTest(unittest.TestCase):
    def test_rejects_cityscapes(self):
        with self.assertRaises(AssertionError):
            validate_names({i: 'wall' for i in range(19)})

    def test_rejects_150_categories_without_door(self):
        with self.assertRaises(AssertionError):
            validate_names({i: f'class{i}' for i in range(150)})

    def test_requires_complete_actual_metadata(self):
        labels = {i: f'class{i}' for i in range(150)}
        labels.update({0: 'wall', 3: 'floor', 5: 'ceiling', 8: 'windowpane', 14: 'door'})
        self.assertEqual(validate_names(labels)[14], 'door')
        labels[151] = labels.pop(149)
        with self.assertRaises(AssertionError): validate_names(labels)

if __name__ == '__main__': unittest.main()
