#!/usr/bin/perl
#################################################################################
#                                                                               #
# MIMIFIR Pierre-Jacques - 14/03/2019                                           #
#                                                                               #
#  Rôle: Gestion des mouvements de bandes DRP pour les PCA/PRA                  #
#                                                                               #
# 1) Check si pas de backup en cours                                            #
# 2) Enveler du robot toutes les bandes DRM montable                            #
# 3) Passer toutes les bandes DRM avec le status vaultretrieve à courierretrieve#
# 4) Envoi du report par mail sur la rotation des bandes du jour                #
#                                                                               #
#################################################################################
use strict;
use warnings;
use POSIX;
use Time::Local;
use Switch;

my $version="1.7";

my $from="pierre-jacques.mimifir.ext\@gmail.com";
my $user="pjmimifir";
my $password="sakura545A33A";
my $log_dir="/var/log/tsm/";
my $dsmadmc="/usr/bin/dsmadmc";
my $tsapi;
my $tsapi_user;
my $tsapi_password;
my $tsapi_host;
my $java;
my $lib;
my $tsm_lib;
my %config;

my @media_imput;
my @media_output;
my @media_ret;

my %drm_media;

my $out_location="LOCARCHIVE";
my $prod_location="X1";

my $body_mail="";
#
#  defined commands
#

my $backup="";
my $list_DRM="q drm";
my $move_DRM__Montable_to_courier="move drm '*' wherestate=mountable tostate=courier tolocation=$out_location wait=yes ";
my $move_DRM__courier_to_vault="move drm '*' wherestate=courier tostate=vault tolocation=$out_location wait=yes ";
my $move_DRM__vault_retieve_to_courier_retrieve="move drm '*' wherestate=vaultretrie tostate=courierretrie tolocation=$out_location wait=yes ";
my $move_DRM__courier_retieve_to_scratch="'move drm * wherestate=courierretr tostate=onsiteret tolocation=$prod_location'";

sub run_dsmadmc_command{
	my $cmd=shift;
        open S,">>var/log/tsm/rotation_$$";
	if(open F,"$cmd |"){
		while(<F>){
			print    $_;
			#print  S  $_;
		}
		close F;
	}
	close S;
	return 0;
}

sub get_process{
	my $cmd="$dsmadmc -id=$user -password=$password  q pr";
	my $found=0;
	open P,"$cmd |" || return undef;
	while(<P>){
		if(/PROCESS: No active processes found/){
			$found=1;
		}
	}
	close P;
}

sub help{
	print "Help:\n";
	print "\t-R\t:Rotation des bandes\n"; 
	print "\t-IR\t:Ajouter les bandes en retour dans Spectrum Protect\n";
	print "\t-h\t:Afficher l'aide\n";
	print "\t-A\t:Lancer un audit TSM de la library\n";
	print "\t-SCV\t:Nous passons les bandes inséreés la veille dans robot et dans l'état COURIERRETIREVE en scratch\n";
	print "\t-I\t:Itégration normale des bandes\n";
	print "\t-C\t:Vérification des bandes dans les slots de chargments\n";
}

sub getEmptyVolumesList{
	my $cmd="$dsmadmc -id=$user -password=$password -comma q vol ";
	my %ref;
	if(open  E,"$cmd |"){
		while(<E>){
			chomp;
			my ($vol,$stgpool,$devclass,$estcapa,$pctutil,$status)=split/,/;
			if(/empty/i){
				$ref{$vol}{PCTUTIL}=$pctutil;
				$ref{$vol}{DEVCLASS}=$devclass;
				$ref{$vol}{STGPOOL}=$stgpool;
				$ref{$vol}{ESTCAPACITY}=$estcapa;
			}
			if(/LTO/i){
				$drm_media{$vol}{PCTUTIL}=$pctutil;
				$drm_media{$vol}{DEVCLASS}=$devclass;
				$drm_media{$vol}{STGPOOL}=$stgpool;
				$drm_media{$vol}{ESTCAPACITY}=$estcapa;
			}
		}
		close E;
	}
	return \%ref;
}

#
# Sortie des bandes DRM montable pour le PRA du site de secours.
# Seules les bandes avec des données sont sorties.
#
sub media_outpout{
	my $drm_medias=get_drm_media_informations();
	my $vol_emptys=getEmptyVolumesList;
	my %data;
	foreach my $vol(keys %{$drm_medias}){
		print $vol;
		my $stat=$drm_medias->{$vol}{STAT};
		next if ( $stat !~ /mountable/i);
		next if (exists $vol_emptys->{$vol}); # le volume n'a pas de données et ne sera dont pas sortie
		my $cmd="$dsmadmc -id=$user -password=$password  $move_DRM__Montable_to_courier";
		print "$vol non vide\n";
		my $logfile="$log_dir/move_DRM__Montable_to_courier.$$.log";
		my $out="$log_dir/move_DRM__Montable_to_courier.out.$$.log";
		$cmd =~ s/\*/$vol/;
		push @media_output,$vol;
		run_dsmadmc_command($cmd);
	}
	return \%data;
}

sub media_imput{
	my $ref=shift;
	#my $cmd="$dsmadmc -id=$user -password=$password  $move_DRM__courier_retieve_to_scratch";
	#my $logfile="$log_dir/move_DRM__courier_retieve_to_scratch.$$.log";
	#my $out="$log_dir/move_DRM__courier_retieve_to_scratch.out.$$.log";
	#run_dsmadmc_command($cmd,$out,$logfile);
	return if not defined $ref;
	foreach my $vol (@media_imput){
		my $cmd1="$dsmadmc -id=$user -password=$password move drm $vol wherestate=courierretr tostate=onsiteret tolocation=$prod_location";
		my $cmd2="$dsmadmc -id=$user -password=$password checkin libv $lib $vol status=scratch checklabel=barcode waitt=0 search=bulk";  
		run_dsmadmc_command($cmd1);
		run_dsmadmc_command($cmd2);
	}
}

sub ask_for_media_retrieve{
	my $cmd="$dsmadmc -id=$user -password=$password '$move_DRM__vault_retieve_to_courier_retrieve'";
	my $logfile="$log_dir/move_DRM__vault_retieve_to_courier_retrieve.$$.log";
	my $out="$log_dir/move_DRM__vault_retieve_to_courier_retrieve.out.$$.log";
	run_dsmadmc_command($cmd);
}

sub media_fault{
	my $cmd="$dsmadmc -id=$user -password=$password $move_DRM__courier_to_vault";
	my $logfile="$log_dir/move_DRM__courier_to_vault.$$.log";
	my $out="$log_dir/move_DRM__courier_to_vault.out.$$.log";
	run_dsmadmc_command($cmd);
}

sub get_drm_media_informations {
	my $cmd="$dsmadmc -id=$user -password=$password -comma q drm";
	open F,"$cmd |" || return undef;
	my %infos;
	while(<F>){
		chomp;
		if(/^(\w+),(\w+|\w+\s+\w+),(\d{2}\/\d{2}\/\d{2})\s+(\d{2}:\d{2}:\d{2})/){
			my $tape=$1;
			my $stat=$2;
			my $last_access_date=$3;
			my $last_access_time=$4;
			$infos{$tape}{NAME}=$tape;
			$infos{$tape}{STAT}=$stat;
			$infos{$tape}{ACCESS_DATE}=$last_access_date;
			$infos{$tape}{ACCESS_TIME}=$last_access_time;
		}
	}
	close F;
	return \%infos;
}

sub to_html{
	my $ref=shift;
	my $title=shift;
	my $drms=get_drm_media_informations();
	my @html;
	push @html,"<table>";
	push @html,"<tr><th>Tape Volume</th><th>Last access date</th><th>Last access time</th></tr>";
	foreach my $tape(keys %{$ref}){
		my $last_date=$drms->{$tape}{ACCESS_DATE};
		my $last_time=$drms->{$tape}{ACCESS_TIME};
		push @html,"<tr><td>$tape</td><td>$last_date</td><td>$last_time</td></tr>";
	}
	push @html,"</table>";
	return \@html;
}

sub SetCourierToVault{
	my $ref=shift;
	my $logfile="/var/log/tsm/setCourierToFault.log";
	return if(not defined $ref);
	foreach my $vol (keys %{$ref}){
		my $vol_stat=$ref->{$vol}{STAT};
		if($vol_stat =~ /^courier$/i){
			my($hour,$min,$sec)=split/\:/,$ref->{$vol}{ACCESS_TIME};
			my($month,$mday,$year)=split/\//,$ref->{$vol}{ACCESS_DATE};
			my $t=timelocal($sec,$min,$hour,$mday,$month-1,$year);
			my $now=time();
			my $diff=($now-$t);
			if($diff > 86400){
				my $cmd="$dsmadmc -id=$user -password=$password $move_DRM__courier_to_vault";
				$cmd =~ s/\*/$vol/i;
				$cmd =~ s/LOG/$logfile/;
				print "Lancement de la commande: $cmd\n";
				run_dsmadmc_command($cmd);
			}
		}
	}
}

sub SetVaultretrieveToCourierRetrieve{
	my $ref=shift;
	my $logfile="/var/log/tsm/setVaultRetrieveToCourierRetrieve.log";
	return if(not defined $ref);
	foreach my $vol (keys %{$ref}){
		my $vol_stat=$ref->{$vol}{STAT};
		#print "$vol --- $vol_stat\n";
		if($vol_stat =~ /vault\s+ret/i){
			my $cmd="$dsmadmc -id=$user -password=$password $move_DRM__vault_retieve_to_courier_retrieve";
			$cmd =~ s/\*/$vol/i;
			$cmd =~ s/LOG/$logfile/;
			print "Lancement de la commande pour le retour des cassettes: $cmd\n";
			push @media_imput,$vol;
			run_dsmadmc_command($cmd);
		}elsif($vol_stat =~ /courier\s+ret/i){
			# On redemande les bandes Qui ne sont toujours pas trouvées dans la $lib
			push @media_imput,$vol;
			print "$vol : $vol_stat\n";
		}
	}
}

sub sendHtmlRepportByMail{
	my $ref=shift;
	my @html;
	my $date=strftime("%d/%m/%Y à %H:%M",localtime(time));
	my $subject="Movement des cassettes PRA du $date";

	push @html,"<! DOCTYPE html>";
	push @html,"<html>";
	push @html,"<head><title>Mouvement des cassettes de PRA</title></head>";
	push @html,"<body style=\"background-color:#ecefef;color:blue;height:100%;padding:5px;margin:1px;\">";

	push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:blue;margin-left:1px;height:100px;font:18px Hervetica\">Mouvement des cassettes de PRA  du $date</div>";
	push @html,"<div style=\"background-color:#ecefef;color:blue\">";
	push @html,"<div style=\"background-color:#eeecfc;color:black;border:1px solid green;	\">";
	push @html,"<h4 style=\"margin:0;padding0;Color:blue\"> Liste des bandes à entrer dans le Robot:</h4>";
	push @html,"<ul style=\"padding:0;Color:blue\">";
	for my $volin(sort @media_imput){
		my $txt=sprintf("%-12s %-45s %-7s",$volin,$drm_media{$volin}{STGPOOL},$drm_media{$volin}{ESTCAPACITY});
		push @html,"<il>$txt</il>";
	}
	push @html,"</ul>";
	push @html,"</div>";

	push @html,"<div style=\"background-color:#eeecfc;border:1px solid green;padding:1px\">";
	push @html,"<h4 style=\"margin:0;padding0;Color:blue\"> Liste des bandes à sortir dans le Robot:</h4>";
	push @html,"<ul style=\"padding:0;Color:blue\">";
	for my $volout(sort @media_output){
		my $txt=sprintf("%-12s %-45s %-7s",$volout,$drm_media{$volout}{STGPOOL},$drm_media{$volout}{ESTCAPACITY});
		push @html,"<il>$txt</il>";
	}
	push @html,"</ul>";
	push @html,"</div>";
	push @html,"</div>";
	push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:white\"> (c) Shana Consulting 2019 Version $version Pierre-Jacques MIMIFIR</div>";
	push @html,"</body>";
	push @html,"</html>";
	my $data=join "\n",@html;

	open  MAIL,"|/usr/sbin/sendmail -t" || return undef;
	print MAIL "To: TSM_exploitation\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject \n";
	print MAIL "Content-Type: text/html; chartset=ISO-8859-1\n\n";
	print MAIL "<pre>\n$data</pre>\n";
	close MAIL;
}

sub send_res_by_mail{
	my $ref=shift;
	my @html;
	my $date=strftime("%d/%m/%Y à %H:%M",localtime(time));
du $date";

	push @html,"<! DOCTYPE html>";
	push @html,"<html>";
	push @html,"<head><title>Mouvement des cassettes de PRA</title></head>";
	push @html,"<body style=\"background-color:#ecefef;color:blue;height:100%;padding:5px;margin:1px;\">";

	push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:blue;margin-left:1px;height:100px;font:18px Hervetica\">Intégration des cassettes en attentes à la du $date</div>";
	push @html,"<div style=\"background-color:#ecefef;color:blue\">";
	push @html,"<div style=\"background-color:#eeecfc;color:black;border:1px solid green;	\">";
	push @html,"<h4 style=\"margin:0;padding0;Color:blue\"> Liste des bandes attendue dans le chargeur:</h4>";
	push @html,"<ul style=\"padding:0;Color:blue\">";
	my @vols=keys %{$ref};
	foreach my $vol (@vols){
		my $txt=sprintf("%-12s %-45s",$vol,$ref->{$vol});
		push @html,"<il>$txt</il>";
	}
	if($#vols == -1){
		push @html,"<il>Aucune bande n'est attendue ce jour.</il>";
	}
	push @html,"</ul>";
	push @html,"</div>";
	push @html,"</div>";
	push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:green\"> (c) Shana Consulting 2019 Version $version Pierre-Jacques MIMIFIR</div>";
	push @html,"</body>";
	push @html,"</html>";
	my $data=join "\n",@html;
	open  MAIL,"|/usr/sbin/sendmail -t" || return undef;
	print MAIL "To: TSM_exploitation\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject \n";
	print MAIL "Content-Type: text/html; chartset=ISO-8859-1\n\n";
	print MAIL "<pre>\n$data</pre>\n";
	close MAIL;
}

sub buld_imputOutputList{
	my $ref=shift;
	return if not  defined $ref;
	foreach my $vol (keys %{$ref}){
		my $stat=$ref->{$vol}{STAT};
		if($stat =~ /^courier\s*\ret/i){
			push @media_imput,$vol;
		}elsif($stat =~ /^vault\s\ret/i){
			push @media_ret,$vol;
		}elsif($stat =~ /^montable/i){
			push @media_output,$vol;
		}

	}
}

sub get_Media_IN_LIB_IO{
	print "Erreur: les variables de l'API TS3310 ne sontt pas toutes définies.\n" if not defined($tsapi and $tsapi_user and $tsapi_password and $tsapi_host);;
	my %data;
	my $command="$java -jar $tsapi -u $tsapi_user -p $tsapi_password -a $tsapi_host --viewIOStation";
	print "$command \n";
	if(open F,"$command |"){
		while(<F>){
			if(/LTO-\d/i){
				chomp;
				s/^\s+|\s+//g;
				my($vol,$lib,$type,$loc)=split/,/;
				#print " [ $vol ] \n";
				$data{$vol}{LIB}=$lib;
				$data{$vol}{TYPE}=$type;
				$data{$vol}{LOC}=$loc;
			}
		}
		close F;
	}
	return \%data;
}

sub get_MediaList_IN_LIBs{
	print "Erreur: les variables de l'API TS3310 ne sont pas toutes définies.\n" if not defined($tsapi and $tsapi_user and $tsapi_password and $tsapi_host);
	my %data;
	if(open F,"$java -jar $tsapi -u $tsapi_user -p tsapi_password -a $tsapi_host --viewDataCartridges|"){
		while(<F>){
			if(/LOT-\d/){
				chomp;
				s/\s+//;
				my($vol,$lib,$type,$stg,$loc,$eaddr,$enc)=split/,/;
				$data{$vol}{LIB}=$lib;
				$data{$vol}{TYPE}=$type;
				$data{$vol}{LOC}=$loc;
			}
		}
		close F;
	}
	return \%data;
}

sub main {
	my $result=`$dsmadmc -id=$user -password=$password  q session`;
	if($? != 0){
		print "Connection Impossible au serveur TSM!\n";
		print "Merci de vérifier les options de connexions user/password.\n";
		exit -1;
	}
	if($#ARGV == -1){
		help();
		exit(-1);
	}
	foreach my $arg(@ARGV){
		switch($arg){
			case ("-R") {
				my $process=get_process();
				while($process == 1){
					print "Des processus TSM sont en cours d'exécussion...\n";
					print "Nous attendons 5 minutes et referons une nouvelle tentative!\n";
					sleep(5*60);
					$process=get_process();
				}
				my $empty_volumes=getEmptyVolumesList();
				my $drm_information=get_drm_media_informations();
				SetCourierToVault($drm_information); # Nous passons les banndes sorties la veille en status Vault
				media_imput(); # Nous ajoutons les bandes ajoutées hiers à TSM qui se Trouve en status CourierRetrieve
				my @text;
				#
				# Sortie des bandes DRM
				#
				media_outpout();	
				#
				#  Nous demandons les bandes à retourner par le prestataire
				#
				SetVaultretrieveToCourierRetrieve($drm_information);
				# Genéraytion de la liste des entrees et des sorties
				push @text,"Liste des bandes à sortir du robot:";
				foreach my $vol(@media_output){
					push @text,"\t$vol";
				}
				push @text,"";
				push @text,"Liste des bandes à entrer du robot:";
				foreach my $vol(@media_imput){
					push @text,"\t$vol";
				}
				sendHtmlRepportByMail($empty_volumes);
			}
			case (/-H|-h/){
				help();
				exit -5;
			}case ("-C"){
				my @html=();
				my $date=strftime("%d/%m/%Y à %H:%M",localtime(time));
				push @html,"<! DOCTYPE html>";
                                push @html,"<html>";
                                push @html,"<head><title>\"Vérification des bandes présentes dans les slots IO robot\"</title></head>";
                                push @html,"<body style=\"background-color:#ecefef;color:blue;height:100%;padding:5px;margin:1px;\">";
                                push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:blue;margin-left:1px;height:100px;font:18px Hervetica\">Date:$date</div>";
                                push @html,"<div style=\"background-color:#ecefef;color:blue\">";
                                push @html,"<div style=\"background-color:#eeecfc;color:black;border:1px solid green;   \">";
                                push @html,"<h4 style=\"margin:0;padding0;Color:blue\">Liste des bandes trouvées:</h4>";
                                push @html,"<ul style=\"padding:0;Color:blue\">";
			 	my $drm_information=get_drm_media_informations();
				my $m_io=get_Media_IN_LIB_IO();
				my $m_lib=get_MediaList_IN_LIBs();
				foreach my $vol(keys %{$m_io}){
					if(exists  $drm_information->{$vol}){
						if($drm_information->{$vol}{STAT} =~ /^Courier$/i){
							push @html,"<il>$vol : Cette bande devrait être en transit vers Locarchive.</il>";
						}elsif($drm_information->{$vol}{STAT} =~ /vault $/i){
							push @html,"<il>$vol : Cette bande devrait être chez Locarchive</il>";
						}else{
							push @html,"<il>$vol : Cette bande sera intégrée lors du prochain checkin!</il>";
						}
					}else{
						push @html,"<il>$vol : Bande non connue!</il>";
					}
				}
				push @html,"<il></il>";
				push @html,"</div></div></ul></h4><div></div></html>";
				my $text=join "\n",@html;
				my $subject="Vérification des bandes bulk";
				my $data=$text;
			 	open  MAIL,"|/usr/sbin/sendmail -t" || return undef;
                                print MAIL "To: TSM_exploitation2\n";
                                print MAIL "From: $from\n";
                                print MAIL "RCPT: $from\n";
                                print MAIL "Subject: $subject \n";
                                print MAIL "Content-Type: text/html; chartset=ISO-8859-1\n\n";
                                print MAIL "<pre>\n$data</pre>\n";
                                while(<MAIL>){
                                        print $_;
                                }
                                close MAIL;


			}case ("-I"){
				my $date=strftime("%d/%m/%Y à %H:%M",localtime(time));
				my %h;
				my $drm_information=get_drm_media_informations();
				#buld_imputOutputList($drm_information);
				my $m_io=get_Media_IN_LIB_IO();
				my $m_lib=get_MediaList_IN_LIBs();
				my @waiting_media;
				foreach my $vol (keys %{$drm_information}){
				if($drm_information->{$vol}{STAT} =~ /courier\s+ret/i){
						$vol =~ s/\s+|^\s+//g;
						#print "[$vol]\n";
						push @waiting_media,$vol;
					}
				}
				my @html;
				push @html,"<! DOCTYPE html>";
				push @html,"<html>";
				push @html,"<head><title>Checkin des cassettes demandées</title></head>";
				push @html,"<body style=\"background-color:#ecefef;color:blue;height:100%;padding:5px;margin:1px;\">";
				push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:blue;margin-left:1px;height:100px;font:18px Hervetica\">Date:$date</div>";
				push @html,"<div style=\"background-color:#ecefef;color:blue\">";
				push @html,"<div style=\"background-color:#eeecfc;color:black;border:1px solid green;	\">";
				push @html,"<h4 style=\"margin:0;padding0;Color:blue\">Bande(s) demandée(s):</h4>";
				push @html,"<ul style=\"padding:0;Color:blue\">";
				foreach my $vol(@waiting_media){
				  push @html,"<il>$vol</il>";
				}
				push @html,"</ul>";
				my @checkin_vol;
				push @html,"<h4 style=\"margin:0;padding0;Color:blue\">Résulat:</h4>";
				push @html,"<ul style=\"padding:0;Color:blue\">";
				foreach my $vol(@waiting_media){
				   if(! exists $m_io->{$vol}){
						print "Le volume $vol est attendu, mais n'a pas été trouvé dans le chargeur du robot\n";
						my $txt=sprintf("%-12s: %-4s",$vol,"KO => Volume absent du robot!");
						push @html,"<il>$txt</il>";
				   }else{
						my $cur_lib=$m_io->{$vol}{LIB};
						if($cur_lib =~ /$lib/){
							my $txt=sprintf("%-12s: %-4s",$vol,"OK");
							push @html,"<il>$txt</il>";
							print "checkin du volume $vol demandé\n";
							push @checkin_vol,$vol;
						}else{
							my $txt=sprintf("%-12s: %-4s",$vol,"KO => Non affectée à la bonne library");
							print "le volume $vol a été trouvé dans le robot, mais n'est pas affecté à la librairie $lib!\n";
							push @html,"<il>$txt</il>";

						}
				   }
				}
				my $res= ((join '\n',@html)  =~ /KO/g) ? "Result du script: OK": "Resultat du script: KO";
				push @html,"<div>.</div>";
				push @html,"<div>.</div>";
				push @html,"<div>$res</div>";
				push @html,"<div style=\"border:1px solid blue;background-color:#ecefef;color:white\">(c) Shana Consulting
				
				
				
				
				2019 Version $version Pierre-Jacques MIMIFIR</div><div></div>";
				push @html,"</html>";

				foreach my $v(@checkin_vol){
 					my $cmd="'move drm $v wherestate=courierretr tostate=onsiteret'";
				        run_dsmadmc_command($cmd);
				}
				foreach my $vol(@checkin_vol){
				  #my $cmd0="$dsmadmc -id=$user -password=$password checkin libv $lib $vol status=scratch checklabel=barcode waitt=0 search=bulk";
				  my $cmd1="$dsmadmc -id=$user -password=$password upd vol $vol access=readw ";
				  #run_dsmadmc_command($cmd0);
				  run_dsmadmc_command($cmd1);
				}	

				 if( $#checkin_vol > -1){
                                 print "Checkin en cours...\n";
                                 my $list=join ",",@checkin_vol;
                                 my $cmd="$dsmadmc -id=$user -password=$password checkin libv $tsm_lib vollist=$list status=scratch checklabel=barcode waitt=0 search=bulk";
                                 run_dsmadmc_command($cmd);
                                }

				my $subject="Checkin des bandes en retour";
				my $data=join "\n",@html;

				open  MAIL,"|/usr/sbin/sendmail -t" || return undef;
			        print MAIL "To: TSM_exploitation2\n";
        			print MAIL "From: $from\n";
        			print MAIL "RCPT: $from\n";
        			print MAIL "Subject: $subject \n";
        			print MAIL "Content-Type: text/html; chartset=ISO-8859-1\n\n";
        			print MAIL "<pre>\n$data</pre>\n";
				while(<MAIL>){
					print $_;
				}
        			close MAIL;

			}
			case ("-IR"){
				my $drm_information=get_drm_media_informations();
				SetVaultretrieveToCourierRetrieve($drm_information);
				$drm_information=get_drm_media_informations();
				print "Checkin des bandes en retour en cours\n";
				print "Recherche des bandes: \n";
				foreach my $vol(keys %{$drm_information}){
					if($drm_information->{$vol}{STAT} =~ /courier\s+ret/i){
						print "\t$vol\n";
						push @media_imput,$vol;
					}
				}
				media_imput($drm_information);
				print "Recherche des bandes terminée\n";
			}case("-A"){
				my $cmd="$dsmadmc -id=$user -password=$password -comma audit libr $lib checklabel=barcode";
				print "Audit de la library $lib en cours.\n";
				run_dsmadmc_command($cmd);
				print "lancement du processus d'audit de la library terminé\n";
			}
			case("-SCV"){
				my $drm_information=get_drm_media_informations();
				SetCourierToVault($drm_information); # Nous passons les bandes sorties la veille en status Vault
			}
			else{
				print "Aucune action n'a été reconnue sur la ligne de commande\n";
				help();
				exit -6;
			}
		}
	}
}

sub exit_{
	print shift;
	exit -1;
}
sub read_config(){
	if(open F,"/home/exploit/etc/K7rotation.conf"){
		while(<F>){
			next if /^#/;
			chomp;
			my ($key,$val)=split/=|:/;
			if(defined $key and defined $val){
				$config{$key}=$val;
				#print "$key :: $val \n";
			}

		}		
		$tsapi= exists $config{tsapi} ? $config{tsapi} : exit_("la variable tsapi n'est pas définie\n");
		$tsapi_host= exists $config{tsapi_host} ? $config{tsapi_host} : exit_("la variable tsapi_host non définie");
		$tsapi_user= exists $config{tsapi_user} ? $config{tsapi_user} : exit_("la variable tsapi_user n'est pas définie\n");
		$tsapi_password= exists $config{tsapi_password} ? $config{tsapi_password} : exit_ ("la variable tsapi_password n'est pas définie\n");;

		$tsm_lib= exists $config{tsm_lib} ? $config{tsm_lib} : exit_ ("la variable tsm_lib n'est pas définie\n");;

		$lib= exists $config{lib} ? $config{lib} : exit_("la variable lib n'est pas définie\n");
		$user= exists $config{user} ? $config{user} : exit_("la variable $user n'est pas définie\n");
		$password= exists $config{password} ? $config{password} : exit_("la variable password n'est pas definie\n");
		$java= exists $config{java} ? $config{java} : exit_("la variable java n'est pas définie\n");
		
		foreach my $var ($tsapi,$java){
		if(!-f $var){
			print "Impossible de trouver : $var\n";
			exit -1;
		}
		}
	}else{
		print "Impossible de trouver de lire ou trouver le fichier de configuration.\n";
		exit -1;
	}
}

read_config();
main;
exit 0;
