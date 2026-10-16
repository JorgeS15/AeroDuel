class_name PlaneType
extends Resource
## Características de um modelo de avião.
## Para criar um avião novo, duplica data/planes/biplane.tres e muda os valores no Inspector.

@export var id := "biplane"           ## identificador usado nas definições guardadas
@export var display_name := "Biplano"
@export_multiline var description := ""
@export_enum("biplane", "fighter", "bomber", "triplane") var style := "biplane"   ## desenho
@export var draw_scale := 1.0         ## tamanho do desenho
@export var hit_radius := 6.0         ## raio de impacto das balas

@export_group("Voo")
@export var thrust := 60.0           ## força do motor
@export var drag := 0.75             ## atrito do ar (velocidade máxima nivelada = thrust / drag)
@export var stall_speed := 26.0      ## abaixo disto entra em perda
@export var takeoff_speed := 40.0    ## velocidade mínima para descolar
@export var turn_rate := 3.0         ## rotação em rad/s

@export_group("Combate")
@export var max_hp := 3
@export var fire_cooldown := 0.2     ## segundos entre tiros
@export var bullet_speed := 170.0
@export var rear_gun := false        ## dispara também uma bala para trás
